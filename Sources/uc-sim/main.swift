import Foundation
import UCCore
let args = CommandLine.arguments
func argument(_ key: String, default value: String) -> String {
    guard let index = args.firstIndex(of:key), index+1 < args.count else { return value }
    return args[index+1]
}
do {
    let scenarios = try SimulationRunner.load(directory: URL(fileURLWithPath:argument("--scenarios",default:"Tests/Scenarios")))
    let map = try FixtureLayoutMap(directory:URL(fileURLWithPath:argument("--layouts",default:"Tests/Fixtures/layouts")))
    let report = try SimulationRunner.run(scenarios,map:map)
    let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
    let output=URL(fileURLWithPath:argument("--report",default:"work/uc-sim-report.json"))
    try FileManager.default.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
    try encoder.encode(report).write(to:output,options:.atomic)
    print("scenarios=\(report.scenarios) passed=\(report.passed) failed=\(report.failed.count)")
    for id in report.failed { print("failed_scenario=\(id)") }
    exit(report.failed.isEmpty ? 0 : 1)
} catch { FileHandle.standardError.write(Data("simulation_failed_invalid_input_or_io\n".utf8)); exit(2) }
