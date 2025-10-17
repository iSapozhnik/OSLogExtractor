import Foundation
import Darwin

#if canImport(UIKit)
import UIKit
#endif
#if canImport(Network)
import Network
#endif

struct MetadataCollector {
    struct Context {
        let bundle: Bundle
        let processInfo: ProcessInfo
        let filter: LogFilter
        let restrictToCurrentProcess: Bool
    }

    func collect(context: Context, statistics: LogMetadata.Statistics) -> LogMetadata {
        LogMetadata(
            app: collectApp(bundle: context.bundle),
            device: collectDevice(processInfo: context.processInfo),
            process: collectProcess(processInfo: context.processInfo),
            resources: collectResources(),
            networking: collectNetworking(),
            loggingScope: collectScope(context: context, statistics: statistics),
            statistics: statistics
        )
    }

    private func collectApp(bundle: Bundle) -> LogMetadata.App? {
        let bundleID = bundle.bundleIdentifier
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if bundleID == nil, displayName == nil, version == nil, build == nil {
            return nil
        }
        return .init(bundleID: bundleID, displayName: displayName, version: version, build: build)
    }

    private func collectDevice(processInfo: ProcessInfo) -> LogMetadata.Device {
        let locale = Locale.current
        let timezone = TimeZone.current.identifier
        let osVersion = processInfo.operatingSystemVersion

        #if canImport(UIKit)
        let device = UIDevice.current
        let batteryLevel = device.isBatteryMonitoringEnabled ? device.batteryLevel : nil
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let batteryState: String
        switch device.batteryState {
        case .charging, .full: batteryState = "charging"
        case .unplugged: batteryState = "unplugged"
        case .unknown: batteryState = "unknown"
        @unknown default: batteryState = "unknown"
        }
        let batteryInfo = batteryLevel.flatMap { level -> LogMetadata.Device.Battery? in
            guard level >= 0 else { return nil }
            return LogMetadata.Device.Battery(level: Double(level), state: batteryState)
        }
        #else
        let batteryInfo: LogMetadata.Device.Battery? = nil
        let lowPower: Bool? = nil
        #endif

        return .init(
            platform: platformName(),
            model: modelIdentifier(),
            osVersion: formatted(osVersion: osVersion),
            locale: locale.identifier,
            region: locale.regionCode,
            timezone: timezone,
            battery: batteryInfo,
            lowPowerMode: lowPower
        )
    }

    private func collectProcess(processInfo: ProcessInfo) -> LogMetadata.Process {
        let launchTime = processInfo.systemUptime > 0 ? Date(timeIntervalSinceNow: -processInfo.systemUptime) : nil
        return .init(
            name: processInfo.processName,
            pid: Int32(getpid()),
            parentPid: Int32(getppid()),
            arch: platformArch(),
            bootTime: bootTime(),
            appLaunchTime: launchTime,
            uptimeSeconds: processInfo.systemUptime,
            threadCount: nil
        )
    }

    private func collectResources() -> LogMetadata.Resources? {
        let physical = ProcessInfo.processInfo.physicalMemory
        let footprint = footprintBytes()
        let free = freeMemoryBytes()

        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        let diskValues = try? homeURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        let memory = LogMetadata.Resources.Memory(
            physical: formatBytes(physical),
            footprint: formatBytes(footprint),
            free: formatBytes(free)
        )

        let totalCap = diskValues?.volumeTotalCapacity
        let freeCap = diskValues?.volumeAvailableCapacity
        let appCap: Int?
        if let documentsURL,
           let values = try? documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            appCap = capacity
        } else {
            appCap = nil
        }

        let disk = LogMetadata.Resources.Disk(
            total: formatBytes(totalCap.map(UInt64.init)),
            free: formatBytes(freeCap.map(UInt64.init)),
            appContainerFree: formatBytes(appCap.map(UInt64.init))
        )

        if memory.physical == nil,
           memory.footprint == nil,
           memory.free == nil,
           disk.total == nil,
           disk.free == nil,
           disk.appContainerFree == nil {
            return nil
        }

        return .init(memory: memory, disk: disk)
    }

    private func collectNetworking() -> LogMetadata.Networking? {
        #if canImport(Network)
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "LogExtractor.NWPathMonitor")
        monitor.start(queue: queue)
        Thread.sleep(forTimeInterval: 0.05)
        let path = monitor.currentPath
        monitor.cancel()
        let reachability: String
        if path.status == .satisfied {
            if path.usesInterfaceType(.wifi) {
                reachability = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                reachability = "cellular"
            } else {
                reachability = "none"
            }
        } else {
            reachability = "none"
        }

        return .init(reachability: reachability, isExpensive: path.isExpensive)
        #else
        return nil
        #endif
    }

    private func collectScope(context: Context, statistics: LogMetadata.Statistics) -> LogMetadata.LoggingScope {
        let filter = LogMetadata.LoggingScope.Filter(
            startDate: context.filter.startDate,
            endDate: context.filter.endDate,
            levels: context.filter.levels,
            subsystem: context.filter.subsystem,
            category: context.filter.category,
            process: context.filter.process,
            contains: context.filter.contains
        )

        let interval: TimeInterval?
        if let start = statistics.firstTimestamp, let end = statistics.lastTimestamp {
            interval = max(0, end.timeIntervalSince(start))
        } else if let start = context.filter.startDate, let end = context.filter.endDate {
            interval = end.timeIntervalSince(start)
        } else {
            interval = nil
        }

        return .init(
            restrictToCurrentProcess: context.restrictToCurrentProcess,
            filter: filter,
            includedIntervalSeconds: interval
        )
    }
}

// MARK: - Helpers

private func platformName() -> String {
    #if os(iOS)
    return "iOS"
    #elseif os(macOS)
    return "macOS"
    #else
    return "unknown"
    #endif
}

private func formatted(osVersion: OperatingSystemVersion) -> String {
    "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
}

private func modelIdentifier() -> String? {
    var size: size_t = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    guard size > 0 else { return nil }
    var machine = [CChar](repeating: 0, count: Int(size))
    sysctlbyname("hw.model", &machine, &size, nil, 0)
    return machine.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return nil }
        return String(cString: base)
    }
}

private func platformArch() -> String? {
    var sysinfo = utsname()
    uname(&sysinfo)
    return withUnsafePointer(to: &sysinfo.machine) { ptr -> String? in
        let int8Ptr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
        return String(cString: int8Ptr)
    }
}

private func bootTime() -> Date? {
    var tv = timeval()
    var size = MemoryLayout<timeval>.stride
    var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
    let result = mib.withUnsafeMutableBufferPointer { ptr -> Int32 in
        sysctl(ptr.baseAddress, 2, &tv, &size, nil, 0)
    }
    guard result == 0 else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
}

private func formatBytes(_ bytes: UInt64?) -> String? {
    guard let bytes else { return nil }
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = .useAll
    formatter.countStyle = .binary
    formatter.includesUnit = true
    formatter.includesCount = true
    return formatter.string(fromByteCount: Int64(bytes))
}

private func footprintBytes() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return info.phys_footprint
}

private func freeMemoryBytes() -> UInt64? {
    var pageSize: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    sysctlbyname("hw.pagesize", &pageSize, &size, nil, 0)

    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: stats) / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return UInt64(stats.free_count) * pageSize
}

private extension LogMetadata.Statistics {
    static var empty: LogMetadata.Statistics {
        .init(
            countsByLevel: .init(debug: 0, info: 0, notice: 0, error: 0, fault: 0),
            topSubsystems: [],
            topCategories: [],
            firstTimestamp: nil,
            lastTimestamp: nil
        )
    }
}
