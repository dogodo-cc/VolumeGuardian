import CoreAudio
import AudioToolbox
import Foundation

// 全局配置：限制最大音量、事件监听队列，以及在系统音量事件不稳定时的短时补偿策略。
private let maximumVolumeScalar: Float32 = 0.2
private let listenerQueue = DispatchQueue(label: "voice.volume-guardian.audio")
private let fallbackClampInterval: TimeInterval = 0.15
private let fallbackClampRepeats = 12

// 用于识别“耳机/耳塞/头戴设备”的关键字；只在匹配到这类输出设备时才强制限幅。
private let headphoneKeywords = [
    "headphone",
    "headphones",
    "headset",
    "airpods",
    "earbuds",
    "buds",
    "耳机"
]

// CoreAudio 很多 API 都要传 AudioObjectPropertyAddress，这里统一封装，减少重复代码。
private func makeAddress(
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope,
    element: AudioObjectPropertyElement
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

final class VolumeGuardian: @unchecked Sendable {
    // 系统级属性地址：用于获取“当前默认输出设备”。
    private static let defaultOutputAddress = makeAddress(
        selector: kAudioHardwarePropertyDefaultOutputDevice,
        scope: kAudioObjectPropertyScopeGlobal,
        element: kAudioObjectPropertyElementMain
    )

    // 设备级监听地址：监听主音量、通道音量，以及数据源变化（例如扬声器/耳机切换）。
    private static let deviceListenerAddresses = [
        makeAddress(
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ),
        makeAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ),
        makeAddress(
            selector: kAudioDevicePropertyDataSource,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
    ]

    // 实际执行限幅时尝试写入的属性集合：主音量，以及左右声道音量。
    private static let clampAddresses = [
        makeAddress(
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ),
        makeAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ),
        makeAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: 1
        ),
        makeAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: 2
        )
    ]

    // 运行时状态：记录当前监听的输出设备，以及短时补偿定时器状态。
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private var currentDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var fallbackClampTimer: DispatchSourceTimer?
    private var fallbackClampRemainingRuns = 0

    // 系统监听器：默认输出设备发生变化时，刷新当前设备并重新绑定监听。
    private lazy var systemListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refreshCurrentDevice()
    }

    // 设备监听器：设备音量或输出源变化时，重新检查是否需要限幅。
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.enforceLimitIfNeeded(trigger: "device change")
    }

    // 程序入口：注册系统监听、初始化当前设备，然后进入主线程事件循环。
    func start() {
        registerSystemListener()
        refreshCurrentDevice()
        print("VolumeGuardian is running. Headphone volume limit: 20")
        dispatchMain()
    }

    // 监听“默认输出设备”这个系统级属性，方便在耳机插拔或切换输出时立即响应。
    private func registerSystemListener() {
        var address = Self.defaultOutputAddress
        let status = AudioObjectAddPropertyListenerBlock(systemObjectID, &address, listenerQueue, systemListener)
        guard status == noErr else {
            fatalError("Failed to register system listener: \(status)")
        }
    }

    // 刷新当前输出设备：如果设备变了，就解绑旧设备监听、绑定新设备监听，并立即执行一次限幅检查。
    private func refreshCurrentDevice() {
        let newDeviceID = defaultOutputDeviceID()
        guard newDeviceID != kAudioObjectUnknown else {
            print("No default output device available.")
            return
        }

        guard currentDeviceID != newDeviceID else {
            enforceLimitIfNeeded(trigger: "output refresh")
            return
        }

        stopFallbackClampTimer()

        if currentDeviceID != kAudioObjectUnknown {
            unregisterDeviceListeners(for: currentDeviceID)
        }

        currentDeviceID = newDeviceID
        registerDeviceListeners(for: newDeviceID)
        print("Monitoring output: \(deviceSummary(for: newDeviceID)) [device id: \(newDeviceID)]")
        enforceLimitIfNeeded(trigger: "output changed")
    }

    // 为当前输出设备注册属性监听，只对设备实际支持的属性进行监听。
    private func registerDeviceListeners(for deviceID: AudioDeviceID) {
        for address in Self.deviceListenerAddresses where hasProperty(objectID: deviceID, address: address) {
            var mutableAddress = address
            let status = AudioObjectAddPropertyListenerBlock(deviceID, &mutableAddress, listenerQueue, deviceListener)
            if status != noErr {
                print("Failed to register device listener for selector \(address.mSelector): \(status)")
            }
        }
    }

    // 切换输出设备时移除旧监听，避免重复回调或监听失效对象。
    private func unregisterDeviceListeners(for deviceID: AudioDeviceID) {
        for address in Self.deviceListenerAddresses where hasProperty(objectID: deviceID, address: address) {
            var mutableAddress = address
            let status = AudioObjectRemovePropertyListenerBlock(deviceID, &mutableAddress, listenerQueue, deviceListener)
            if status != noErr && status != kAudioHardwareBadObjectError {
                print("Failed to remove device listener for selector \(address.mSelector): \(status)")
            }
        }
    }

    // 核心策略：仅当当前输出被识别为耳机类设备时，才把音量限制在预设上限以内。
    private func enforceLimitIfNeeded(trigger: String) {
        let deviceID = currentDeviceID == kAudioObjectUnknown ? defaultOutputDeviceID() : currentDeviceID
        guard deviceID != kAudioObjectUnknown else {
            return
        }

        guard isHeadphoneOutput(deviceID: deviceID) else {
            stopFallbackClampTimer()
            return
        }

        if clampVolume(on: deviceID, maximumScalar: maximumVolumeScalar) {
            scheduleFallbackClamp(for: deviceID)
            print("Clamped volume to 20 for \(deviceSummary(for: deviceID)) [\(trigger)]")
        }
    }

    // 某些设备在刚切换或拖动系统音量时会连续回写音量，这里用一个短时定时器做补偿性重复限幅。
    private func scheduleFallbackClamp(for deviceID: AudioDeviceID) {
        fallbackClampRemainingRuns = fallbackClampRepeats

        if fallbackClampTimer != nil {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: listenerQueue)
        timer.schedule(deadline: .now() + fallbackClampInterval, repeating: fallbackClampInterval)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            guard self.fallbackClampRemainingRuns > 0 else {
                self.stopFallbackClampTimer()
                return
            }

            guard self.currentDeviceID == deviceID, self.isHeadphoneOutput(deviceID: deviceID) else {
                self.stopFallbackClampTimer()
                return
            }

            self.fallbackClampRemainingRuns -= 1
            _ = self.clampVolume(on: deviceID, maximumScalar: maximumVolumeScalar)
        }

        fallbackClampTimer = timer
        timer.resume()
    }

    // 停止补偿性限幅定时器，并清空剩余次数。
    private func stopFallbackClampTimer() {
        fallbackClampTimer?.cancel()
        fallbackClampTimer = nil
        fallbackClampRemainingRuns = 0
    }

    // 依次尝试限制主音量和左右声道音量；只要有任一属性被成功压到上限，就返回 true。
    private func clampVolume(on deviceID: AudioDeviceID, maximumScalar: Float32) -> Bool {
        var changed = false

        for address in Self.clampAddresses {
            changed = clampScalarProperty(objectID: deviceID, address: address, maximumScalar: maximumScalar) || changed
        }

        return changed
    }

    // 先读取当前音量，只有超过上限时才写回，避免无意义的属性写操作。
    private func clampScalarProperty(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        maximumScalar: Float32
    ) -> Bool {
        guard let currentValue = scalarProperty(objectID: objectID, address: address), currentValue > maximumScalar else {
            return false
        }

        return setScalarProperty(objectID: objectID, address: address, value: maximumScalar)
    }

    // 读取系统当前默认输出设备 ID，是整套逻辑的设备入口。
    private func defaultOutputDeviceID() -> AudioDeviceID {
        var address = Self.defaultOutputAddress
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : AudioDeviceID(kAudioObjectUnknown)
    }

    // 通过设备名和当前输出源名匹配关键字，判断当前输出是否应被视为耳机类设备。
    private func isHeadphoneOutput(deviceID: AudioDeviceID) -> Bool {
        let labels = [deviceName(for: deviceID), currentOutputSourceName(for: deviceID)]
            .compactMap { $0?.lowercased() }

        return headphoneKeywords.contains { keyword in
            labels.contains { $0.contains(keyword) }
        }
    }

    // 生成用于日志打印的设备摘要，优先显示“设备名 / 当前输出源名”。
    private func deviceSummary(for deviceID: AudioDeviceID) -> String {
        let deviceLabel = deviceName(for: deviceID) ?? "Unknown device"
        guard let sourceLabel = currentOutputSourceName(for: deviceID), !sourceLabel.isEmpty, sourceLabel != deviceLabel else {
            return deviceLabel
        }
        return "\(deviceLabel) / \(sourceLabel)"
    }

    // 读取设备名称，例如内建扬声器、AirPods、USB 耳机等。
    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = makeAddress(
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanagedName else {
            return nil
        }
        return unmanagedName.takeUnretainedValue() as String
    }

    // 读取当前输出源名称，例如同一设备下的 Speaker / Headphones 等具体路由。
    private func currentOutputSourceName(for deviceID: AudioDeviceID) -> String? {
        var sourceAddress = makeAddress(
            selector: kAudioDevicePropertyDataSource,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        guard hasProperty(objectID: deviceID, address: sourceAddress) else {
            return nil
        }

        var sourceID: UInt32 = 0
        var sourceSize = UInt32(MemoryLayout<UInt32>.size)
        let sourceStatus = AudioObjectGetPropertyData(deviceID, &sourceAddress, 0, nil, &sourceSize, &sourceID)
        guard sourceStatus == noErr else {
            return nil
        }

        var nameAddress = makeAddress(
            selector: kAudioDevicePropertyDataSourceNameForIDCFString,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        let nameStatus = withUnsafeMutablePointer(to: &sourceID) { sourcePointer in
            withUnsafeMutablePointer(to: &unmanagedName) { namePointer in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(sourcePointer),
                    mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
                    mOutputData: UnsafeMutableRawPointer(namePointer),
                    mOutputDataSize: UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                )
                var translationSize = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &translationSize, &translation)
            }
        }

        guard nameStatus == noErr, let unmanagedName else {
            return nil
        }

        return unmanagedName.takeUnretainedValue() as String
    }

    // 读取某个浮点型音量属性；如果设备不支持该属性或读取失败，则返回 nil。
    private func scalarProperty(objectID: AudioObjectID, address: AudioObjectPropertyAddress) -> Float32? {
        guard hasProperty(objectID: objectID, address: address) else {
            return nil
        }

        var mutableAddress = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(objectID, &mutableAddress, 0, nil, &size, &value)
        guard status == noErr else {
            return nil
        }
        return value
    }

    // 向 CoreAudio 写入新的音量值；失败时打印日志，便于排查某些设备不支持写入的问题。
    private func setScalarProperty(objectID: AudioObjectID, address: AudioObjectPropertyAddress, value: Float32) -> Bool {
        var mutableAddress = address
        var mutableValue = value
        let size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(objectID, &mutableAddress, 0, nil, size, &mutableValue)
        if status != noErr {
            print("Failed to set selector \(address.mSelector) on object \(objectID): \(status)")
        }
        return status == noErr
    }

    // 通用能力检测：判断某个 CoreAudio 对象是否支持指定属性。
    private func hasProperty(objectID: AudioObjectID, address: AudioObjectPropertyAddress) -> Bool {
        var mutableAddress = address
        return AudioObjectHasProperty(objectID, &mutableAddress)
    }
}

// 创建守护实例并启动监听。
let guardian = VolumeGuardian()
guardian.start()
