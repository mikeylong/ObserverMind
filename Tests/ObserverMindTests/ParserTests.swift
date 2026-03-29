import Testing
@testable import ObserverMind

@Test func topParserExtractsCPUAndProcesses() throws {
    let fixtureText = try fixture("top.txt")
    let parsed = Parser.parseTop(fixtureText)

    #expect(parsed.cpu.userPercent == 19.37)
    #expect(parsed.cpu.systemPercent == 17.12)
    #expect(parsed.cpu.loadAverage1m == 4.96)
    #expect(parsed.processes.count == 5)
    #expect(parsed.processes.first?.command == "node")
}

@Test func vmStatAndMemoryPressureParsersExtractMemoryMetrics() throws {
    let vmStat = Parser.parseVMStat(try fixture("vm_stat.txt"))
    let pressure = Parser.parseMemoryPressure(try fixture("memory_pressure.txt"))

    #expect(vmStat.pageSize == 16_384)
    #expect(vmStat.pagesFree == 7_706)
    #expect(vmStat.swapouts == 588_670)
    #expect(pressure.freePercent == 87)
}

@Test func nettopBatteryThermalAndHostParsersWork() throws {
    let network = Parser.parseNettop(try fixture("nettop.txt"))
    let battery = Parser.parseBattery(try fixture("pmset_batt.txt"))
    let thermal = Parser.parseThermal(try fixture("pmset_therm.txt"))
    let host = Parser.parseHostSnapshot(
        hardwareText: try fixture("system_profiler.txt"),
        osVersion: "26.4",
        architecture: "arm64"
    )

    #expect(network.first?.command == "launchd")
    #expect(network[1].pid == 589)
    #expect(battery.powerSource == "Battery Power")
    #expect(battery.percentage == 79)
    #expect(thermal.state == "Nominal")
    #expect(host.chip == "Apple M3 Max")
    #expect(host.gpuCoreCount == 40)
}

@Test func powermetricsParserHandlesSyntheticMetrics() throws {
    let parsed = Parser.parsePowermetrics(try fixture("powermetrics.txt"))

    #expect(parsed.cpuPowerWatts == 12.5)
    #expect(parsed.gpuPowerWatts == 8.25)
    #expect(parsed.anePowerWatts == 1.5)
    #expect(parsed.thermalState == "Nominal")
    #expect(parsed.perProcessMetrics[4321]?.energy == 4.2)
    #expect(parsed.perProcessMetrics[4321]?.gpuTime == 12.0)
}
