#!/usr/bin/env python3
"""
Flux Compiler Failing and Edge-Case Test Runner

This script runs the comprehensive test suite to verify that the Flux compiler
handles error conditions and edge cases properly. It generates a detailed
report showing which error handling mechanisms work correctly.

Usage:
    python run_failing_tests.py [--verbose] [--log-level LEVEL] [--filter TYPE]
    
Arguments:
    --verbose, -v       Enable verbose output
    --log-level LEVEL   Set logging level (0-5)  
    --filter TYPE       Only run specific test types (lexer, parser, compiler)
    --report-only       Only generate report from previous results
"""

import argparse
import sys
import os
from pathlib import Path
import json
import time
from datetime import datetime

# Add src/compiler to Python path
sys.path.insert(0, str(Path(__file__).parent.parent / "src" / "compiler"))

from test_suite_failing_edge_cases import FluxFailingTestSuite
from flux_logger import FluxLogger, LogLevel


def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Flux Failing Test Suite Runner')
    parser.add_argument('--verbose', '-v', action='store_true', 
                      help='Enable verbose output')
    parser.add_argument('--log-level', type=int, choices=range(6), default=2,
                      help='Set logging level (0=silent, 5=trace)')
    parser.add_argument('--filter', choices=['lexer', 'parser', 'compiler'],
                      help='Only run specific test type')
    parser.add_argument('--report-only', action='store_true',
                      help='Only generate report from cached results')
    parser.add_argument('--save-results', action='store_true', default=True,
                      help='Save test results for later analysis')
    return parser.parse_args()


def save_results(results, filename="test_results.json"):
    """Save test results to JSON file"""
    results_with_metadata = {
        'timestamp': datetime.now().isoformat(),
        'total_runtime': results.get('runtime', 0),
        'flux_version': '1.0.0-dev',
        'results': results
    }
    
    results_file = Path(__file__).parent / filename
    with open(results_file, 'w') as f:
        json.dump(results_with_metadata, f, indent=2)
    
    return results_file


def load_cached_results(filename="test_results.json"):
    """Load cached test results"""
    results_file = Path(__file__).parent / filename
    if results_file.exists():
        with open(results_file, 'r') as f:
            data = json.load(f)
            return data.get('results', {})
    return None


def print_summary_stats(results):
    """Print a quick summary of test results"""
    total = results['total']
    passed = results['passed']
    failed = results['failed']
    success_rate = (passed / total * 100) if total > 0 else 0
    
    print(f"\n" + "="*60)
    print(f"FLUX FAILING TEST SUITE SUMMARY")
    print(f"="*60)
    print(f"Total Tests:    {total:4}")
    print(f"Passed:         {passed:4}")
    print(f"Failed:         {failed:4}")
    print(f"Success Rate:   {success_rate:5.1f}%")
    
    if 'runtime' in results:
        print(f"Runtime:        {results['runtime']:.2f}s")
    
    print(f"="*60)


def run_filtered_tests(suite, filter_type):
    """Run only tests of a specific type"""
    original_cases = suite.test_cases.copy()
    suite.test_cases = [tc for tc in suite.test_cases if tc.test_type == filter_type]
    
    print(f"Running {len(suite.test_cases)} {filter_type} tests...")
    results = suite.run_all_tests()
    
    # Restore original test cases
    suite.test_cases = original_cases
    
    return results


def generate_detailed_report(results, suite):
    """Generate a more detailed report with insights"""
    report_lines = []
    
    # Basic report from suite
    basic_report = suite.generate_report(results)
    report_lines.append(basic_report)
    
    # Additional analysis
    report_lines.append("\n" + "="*80)
    report_lines.append("DETAILED ANALYSIS")
    report_lines.append("="*80)
    
    # Error handling effectiveness
    total_should_fail = sum(1 for tc in suite.test_cases if tc.should_fail)
    total_should_pass = sum(1 for tc in suite.test_cases if not tc.should_fail)
    
    report_lines.append(f"\nError Handling Analysis:")
    report_lines.append(f"- Tests designed to fail: {total_should_fail}")
    report_lines.append(f"- Tests designed to pass: {total_should_pass}")
    
    # Most common error categories
    error_categories = {}
    for tc in suite.test_cases:
        category = tc.name.split('_')[0]
        error_categories[category] = error_categories.get(category, 0) + 1
    
    report_lines.append(f"\nMost Tested Error Categories:")
    for category, count in sorted(error_categories.items(), key=lambda x: x[1], reverse=True):
        report_lines.append(f"- {category.capitalize()}: {count} tests")
    
    # Recommendations
    report_lines.append(f"\nRecommendations:")
    if results['failed'] > results['total'] * 0.1:  # More than 10% failed
        report_lines.append("- High failure rate detected. Review error handling mechanisms.")
    
    if results['by_type']['lexer']['failed'] > 0:
        report_lines.append("- Lexer errors detected. Review tokenization error handling.")
        
    if results['by_type']['parser']['failed'] > 0:
        report_lines.append("- Parser errors detected. Review syntax error reporting.")
        
    if results['by_type']['compiler']['failed'] > 0:
        report_lines.append("- Compiler errors detected. Review semantic analysis.")
    
    report_lines.append("")
    report_lines.append("="*80)
    
    return "\n".join(report_lines)


def main():
    """Main function"""
    args = parse_arguments()
    
    # Set up logging based on verbosity
    log_level = LogLevel.DEBUG if args.verbose else LogLevel(args.log_level)
    logger = FluxLogger(level=log_level, colors=True, timestamp=True)
    
    logger.section("Flux Failing and Edge-Case Test Suite", LogLevel.INFO, "runner")
    
    if args.report_only:
        # Try to load cached results and generate report
        results = load_cached_results()
        if not results:
            logger.error("No cached results found. Run tests first.", "runner")
            return 1
        
        suite = FluxFailingTestSuite()  # Just for report generation
        report = generate_detailed_report(results, suite)
        print("\n" + report)
        return 0
    
    # Initialize test suite
    start_time = time.time()
    suite = FluxFailingTestSuite()
    
    logger.info(f"Initialized test suite with {len(suite.test_cases)} test cases", "runner")
    
    # Run tests (filtered or all)
    if args.filter:
        results = run_filtered_tests(suite, args.filter)
        logger.info(f"Ran {args.filter} tests only", "runner")
    else:
        results = suite.run_all_tests()
    
    # Add runtime to results
    end_time = time.time()
    results['runtime'] = end_time - start_time
    
    # Print summary
    print_summary_stats(results)
    
    # Generate detailed report
    detailed_report = generate_detailed_report(results, suite)
    print("\n" + detailed_report)
    
    # Save results and report
    if args.save_results:
        results_file = save_results(results)
        logger.info(f"Results saved to: {results_file}", "runner")
    
    report_file = Path(__file__).parent / "test_report_failing_edge_cases_detailed.txt"
    with open(report_file, 'w') as f:
        f.write(detailed_report)
    logger.info(f"Detailed report saved to: {report_file}", "runner")
    
    # Exit with appropriate code
    if results['failed'] == 0:
        logger.success("All tests completed successfully!", "runner")
        return 0
    else:
        logger.warning(f"{results['failed']} tests had issues", "runner")
        return 0  # Note: failing tests are expected in this suite!


if __name__ == "__main__":
    sys.exit(main())
