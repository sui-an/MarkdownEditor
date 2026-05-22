import Foundation

// MARK: - Simple test framework (no XCTest dependency)
var testResults: (passed: Int, failed: Int) = (0, 0)

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: String = #file, line: Int = #line) {
    if actual == expected {
        testResults.passed += 1
    } else {
        testResults.failed += 1
        print("❌ \(message)")
        print("   Expected: \(expected)")
        print("   Actual:   \(actual)")
    }
}

func assertTrue(_ actual: Bool, _ message: String, file: String = #file, line: Int = #line) {
    assertEqual(actual, true, message, file: file, line: line)
}

func assertFalse(_ actual: Bool, _ message: String, file: String = #file, line: Int = #line) {
    assertEqual(actual, false, message, file: file, line: line)
}

func assertNotNil<T>(_ actual: T?, _ message: String, file: String = #file, line: Int = #line) {
    if actual != nil {
        testResults.passed += 1
    } else {
        testResults.failed += 1
        print("❌ \(message) — expected non-nil, got nil")
    }
}
