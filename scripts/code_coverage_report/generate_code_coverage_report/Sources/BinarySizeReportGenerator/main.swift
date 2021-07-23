/*
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import ArgumentParser
import Foundation
import Utils

private enum Constants {}

extension Constants {
  // Binary Size Metrics flag for the Metrics Service.
  static let metric = "BinarySize"
  static let cocoapodSizeReportFile = "binary_report.json"
}

/// Pod Config
struct PodConfigs: Codable {
  let pods: [Pod]
}

struct Pod: Codable {
  let sdk: String
  let path: String
}

/// Cocoapods-size tool report,
struct SDKBinaryReport: Codable {
  let combinedPodsExtraSize: Int

  enum CodingKeys: String, CodingKey {
    case combinedPodsExtraSize = "combined_pods_extra_size"
  }
}

/// Metrics Service API request data
struct BinaryMetricsReport: Codable {
  let metric: String
  let results: [Result]
  let log: String
}

struct Result: Codable {
  let sdk, type: String
  let value: Int
}

struct BinarySizeReportGenerator: ParsableCommand {
  @Option(
    help: "Cocoapods-size tool directory from https://github.com/google/cocoapods-size.",
    transform: URL.init(fileURLWithPath:)
  )
  var binarySizeToolDir: URL

  @Option(help: "Local SDK repo.", transform: URL.init(fileURLWithPath:))
  var SDKRepoDir: URL

  @Option(parsing: .upToNextOption, help: "SDKs to be measured.")
  var SDK: [String]

  @Option(help: "SDKs to be measured.")
  var logPath: String

  func CreatePodConfigJSON(of sdks: [String], from sdk_dir: URL) throws {
    var pods: [Pod] = []
    for sdk in sdks {
      let pod: Pod = Pod(sdk: sdk, path: sdk_dir.path)
      pods.append(pod)
    }
    let podConfigs: PodConfigs = PodConfigs(pods: pods)
    try JSONParser.writeJSON(of: podConfigs, to: "./cocoapods_source_config.json")
  }

  // Create a JSON format data prepared to send to the Metrics Service.
  func CreateMetricsRequestData(of sdks: [String], type: String, log: String) throws -> Data {
    var reports: [Result] = []
    // Create a report for each individual SDK and collect all of them into reports.
    for sdk in sdks {
      // Create a report, generated by cocoapods-size, for each SDK. `.stdout` is used
      // since `pipe` could cause the tool to hang. That is probably caused by cocopod-size
      // is using pipe and a pipe is shared by multiple parent/child process and cause
      // deadlock. `.stdout` is a quick way to resolve at the moment. The difference is
      // `.stdout` will print out logs in the console while pipe can guide logs a variable.
      Shell.run(
        "cd cocoapods-size && python3 measure_cocoapod_size.py --cocoapods \(sdk) --cocoapods_source_config ../cocoapods_source_config.json --json \(Constants.cocoapodSizeReportFile)",
        stdout: .stdout
      )
      let SDKBinarySize = try JSONParser.readJSON(
        of: SDKBinaryReport.self,
        from: "cocoapods-size/\(Constants.cocoapodSizeReportFile)"
      )
      // Append reports for data for API request to the Metrics Service.
      reports.append(Result(sdk: sdk, type: type, value: SDKBinarySize.combinedPodsExtraSize))
    }
    let metricsRequestReport = BinaryMetricsReport(
      metric: Constants.metric,
      results: reports,
      log: log
    )
    let data = try JSONEncoder().encode(metricsRequestReport)
    return data
  }

  func run() throws {
    try CreatePodConfigJSON(of: SDK, from: SDKRepoDir)
    let data = try CreateMetricsRequestData(
      of: SDK,
      type: "firebase-ios-sdk-testing",
      log: logPath
    )
    // TODO: Apply the data to API request sent to the Metrics Service.
    print(String(decoding: data, as: UTF8.self))
  }
}

BinarySizeReportGenerator.main()
