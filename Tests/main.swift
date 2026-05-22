import Foundation

// Run all tests
print("========================================")
print("  MarkdownEditor — Test Suite")
print("========================================\n")

ParserTests.run()
// FeatureTests need MainActor because DocumentController is @MainActor
MainActor.assumeIsolated {
    FeatureTests.run()
}

print("========================================")
print("  Result: \(testResults.passed) passed, \(testResults.failed) failed")
print("========================================")

exit(testResults.failed > 0 ? 1 : 0)
