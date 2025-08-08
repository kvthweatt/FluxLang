#!/usr/bin/env python3
"""
Comprehensive Failing and Edge-Case Test Suite for Flux Compiler

This test suite contains intentionally failing test cases and edge cases
to verify that the Flux compiler properly handles error conditions and
unusual inputs.

Copyright (C) 2025 Flux Language Project
"""

import sys
import os
import tempfile
import subprocess
from pathlib import Path
from typing import List, Dict, Any
import unittest

# Add src/compiler to Python path
sys.path.insert(0, str(Path(__file__).parent.parent / "src" / "compiler"))

from flexer import FluxLexer, TokenType, Token
from fparser import FluxParser, ParseError
from fc import FluxCompiler
from flux_logger import FluxLogger, LogLevel


class FluxTestCase:
    """Container for a single Flux test case"""
    def __init__(self, name: str, code: str, expected_error: str = None, 
                 should_fail: bool = True, test_type: str = "syntax"):
        self.name = name
        self.code = code
        self.expected_error = expected_error
        self.should_fail = should_fail
        self.test_type = test_type  # "lexer", "parser", "compiler", "runtime"


class FluxFailingTestSuite:
    """Comprehensive test suite for Flux compiler failure modes and edge cases"""
    
    def __init__(self):
        self.test_cases: List[FluxTestCase] = []
        self.logger = FluxLogger(level=LogLevel.ERROR, colors=True)
        self._build_test_cases()
    
    def _build_test_cases(self):
        """Build all test cases for the suite"""
        
        # === LEXER FAILURE CASES ===
        self.test_cases.extend([
            FluxTestCase(
                "lexer_unterminated_string",
                'def main() -> int { return "unterminated string; };',
                "Unterminated string literal",
                test_type="lexer"
            ),
            
            FluxTestCase(
                "lexer_unterminated_char",
                "def main() -> int { char c = 'x; return 0; };",
                "Unterminated character literal",
                test_type="lexer"
            ),
            
            FluxTestCase(
                "lexer_invalid_escape_sequence",
                'def main() -> int { return "\\z"; };',
                "Invalid escape sequence",
                test_type="lexer"
            ),
            
            FluxTestCase(
                "lexer_invalid_number_format",
                "def main() -> int { int x = 123.45.67; return 0; };",
                "Invalid number format",
                test_type="lexer"
            ),
            
            FluxTestCase(
                "lexer_unicode_in_identifier",
                "def maîn() -> int { return 0; };",
                "Invalid character in identifier",
                test_type="lexer"
            ),
            
            FluxTestCase(
                "lexer_null_character",
                "def main() -> int { return 0\x00; };",
                "Null character not allowed",
                test_type="lexer"
            ),
        ])
        
        # === PARSER FAILURE CASES ===
        self.test_cases.extend([
            FluxTestCase(
                "parser_missing_semicolon",
                "def main() -> int { return 0 }",
                "Expected semicolon",
                test_type="parser"
            ),
            
            FluxTestCase(
                "parser_unmatched_braces",
                "def main() -> int { return 0; }",
                "Unmatched braces",
                test_type="parser"
            ),
            
            FluxTestCase(
                "parser_missing_return_type",
                "def main() { return 0; };",
                "Missing return type",
                test_type="parser"
            ),
            
            FluxTestCase(
                "parser_invalid_function_name",
                "def 123main() -> int { return 0; };",
                "Invalid function name",
                test_type="parser"
            ),
            
            FluxTestCase(
                "parser_duplicate_parameter",
                "def test(int x, int x) -> int { return 0; };",
                "Duplicate parameter name",
                test_type="parser"
            ),
            
            FluxTestCase(
                "parser_missing_function_body",
                "def main() -> int;",
                "Missing function body",
                test_type="parser"
            ),
            
            FluxTestCase(
                "parser_nested_functions",
                """def main() -> int {
                    def nested() -> int { return 1; };
                    return nested();
                };""",
                "Nested functions not allowed",
                test_type="parser"
            ),
            
            FluxTestCase(
                "parser_invalid_expression",
                "def main() -> int { return 5 + + 3; };",
                "Invalid expression",
                test_type="parser"
            ),
            
            FluxTestCase(
                "parser_missing_parentheses",
                "def main -> int { return 0; };",
                "Missing parentheses in function signature",
                test_type="parser"
            ),
            
            FluxTestCase(
                "parser_incomplete_if_statement",
                "def main() -> int { if return 0; };",
                "Incomplete if statement",
                test_type="parser"
            ),
        ])
        
        # === TYPE SYSTEM EDGE CASES ===
        self.test_cases.extend([
            FluxTestCase(
                "type_void_return_with_value",
                "def test() -> void { return 42; };",
                "void function cannot return a value",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "type_non_void_missing_return",
                "def test() -> int { int x = 5; };",
                "Non-void function must return a value",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "type_mismatched_return",
                "def test() -> int { return \"hello\"; };",
                "Return type mismatch",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "type_undefined_variable",
                "def main() -> int { return undefinedVar; };",
                "Undefined variable",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "type_redeclared_variable",
                "def main() -> int { int x = 5; int x = 10; return x; };",
                "Variable already declared",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "type_invalid_assignment",
                "def main() -> int { int x; x = \"string\"; return x; };",
                "Type mismatch in assignment",
                test_type="compiler"
            ),
        ])
        
        # === CONTROL FLOW EDGE CASES ===
        self.test_cases.extend([
            FluxTestCase(
                "control_unreachable_code",
                """def main() -> int {
                    return 0;
                    int unreachable = 42;
                };""",
                "Unreachable code detected",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "control_break_outside_loop",
                "def main() -> int { break; return 0; };",
                "break statement outside of loop",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "control_continue_outside_loop",
                "def main() -> int { continue; return 0; };",
                "continue statement outside of loop",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "control_infinite_recursion",
                """def infinite() -> int {
                    return infinite();
                };
                def main() -> int {
                    return infinite();
                };""",
                "Potential infinite recursion detected",
                test_type="compiler"
            ),
        ])
        
        # === EDGE CASES WITH VALID SYNTAX BUT PROBLEMATIC SEMANTICS ===
        self.test_cases.extend([
            FluxTestCase(
                "edge_empty_function",
                "def empty() -> void { };",
                None,
                should_fail=False,
                test_type="compiler"
            ),
            
            FluxTestCase(
                "edge_maximum_nested_braces",
                "def main() -> int { { { { { { return 0; } } } } } };",
                None,
                should_fail=False,
                test_type="parser"
            ),
            
            FluxTestCase(
                "edge_long_identifier",
                f"def {'a' * 1000}() -> int {{ return 0; }};",
                "Identifier too long",
                test_type="lexer"
            ),
            
            FluxTestCase(
                "edge_many_parameters",
                f"def test({', '.join(f'int param{i}' for i in range(100))}) -> int {{ return 0; }};",
                "Too many parameters",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "edge_very_large_number",
                "def main() -> int { return 999999999999999999999999999999999; };",
                "Number too large",
                test_type="lexer"
            ),
        ])
        
        # === IMPORT AND NAMESPACE EDGE CASES ===
        self.test_cases.extend([
            FluxTestCase(
                "import_nonexistent_file",
                'import "nonexistent_file.fx"; def main() -> int { return 0; };',
                "File not found",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "import_circular_dependency",
                'import "test_circular.fx"; def main() -> int { return 0; };',
                "Circular import detected",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "namespace_invalid_name",
                "namespace 123invalid { def test() -> void; };",
                "Invalid namespace name",
                test_type="parser"
            ),
        ])
        
        # === OPERATOR EDGE CASES ===
        self.test_cases.extend([
            FluxTestCase(
                "operator_division_by_zero",
                "def main() -> int { return 5 / 0; };",
                "Division by zero",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "operator_modulo_by_zero",
                "def main() -> int { return 5 % 0; };",
                "Modulo by zero",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "operator_invalid_increment",
                "def main() -> int { return ++5; };",
                "Cannot increment literal",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "operator_chained_assignment",
                "def main() -> int { int a, b; a = b = 5; return a; };",
                "Chained assignment not supported",
                test_type="parser"
            ),
        ])
        
        # === MEMORY AND POINTER EDGE CASES ===
        self.test_cases.extend([
            FluxTestCase(
                "memory_null_dereference",
                "def main() -> int { int* ptr = null; return *ptr; };",
                "Null pointer dereference",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "memory_double_free",
                """def main() -> int {
                    int* ptr = malloc(sizeof(int));
                    free(ptr);
                    free(ptr);
                    return 0;
                };""",
                "Double free detected",
                test_type="compiler"
            ),
            
            FluxTestCase(
                "memory_use_after_free",
                """def main() -> int {
                    int* ptr = malloc(sizeof(int));
                    free(ptr);
                    return *ptr;
                };""",
                "Use after free",
                test_type="compiler"
            ),
        ])
    
    def run_lexer_test(self, test_case: FluxTestCase) -> bool:
        """Run a lexer test case"""
        try:
            lexer = FluxLexer(test_case.code)
            tokens = list(lexer.tokenize())
            
            if test_case.should_fail:
                self.logger.error(f"LEXER TEST FAILED: {test_case.name} - Expected failure but succeeded", "test")
                return False
            else:
                self.logger.info(f"LEXER TEST PASSED: {test_case.name}", "test")
                return True
                
        except Exception as e:
            if test_case.should_fail:
                if test_case.expected_error and test_case.expected_error.lower() not in str(e).lower():
                    self.logger.warning(f"LEXER TEST WARNING: {test_case.name} - Wrong error: {e}", "test")
                    return False
                else:
                    self.logger.info(f"LEXER TEST PASSED: {test_case.name} - Failed as expected: {e}", "test")
                    return True
            else:
                self.logger.error(f"LEXER TEST FAILED: {test_case.name} - Unexpected failure: {e}", "test")
                return False
    
    def run_parser_test(self, test_case: FluxTestCase) -> bool:
        """Run a parser test case"""
        try:
            lexer = FluxLexer(test_case.code)
            tokens = list(lexer.tokenize())
            parser = FluxParser(tokens)
            ast = parser.parse()
            
            if test_case.should_fail:
                self.logger.error(f"PARSER TEST FAILED: {test_case.name} - Expected failure but succeeded", "test")
                return False
            else:
                self.logger.info(f"PARSER TEST PASSED: {test_case.name}", "test")
                return True
                
        except Exception as e:
            if test_case.should_fail:
                if test_case.expected_error and test_case.expected_error.lower() not in str(e).lower():
                    self.logger.warning(f"PARSER TEST WARNING: {test_case.name} - Wrong error: {e}", "test")
                    return False
                else:
                    self.logger.info(f"PARSER TEST PASSED: {test_case.name} - Failed as expected: {e}", "test")
                    return True
            else:
                self.logger.error(f"PARSER TEST FAILED: {test_case.name} - Unexpected failure: {e}", "test")
                return False
    
    def run_compiler_test(self, test_case: FluxTestCase) -> bool:
        """Run a full compiler test case"""
        try:
            # Create temporary file
            with tempfile.NamedTemporaryFile(mode='w', suffix='.fx', delete=False) as f:
                f.write(test_case.code)
                temp_file = f.name
            
            try:
                # Create compiler with minimal logging to avoid spam
                compiler = FluxCompiler(logger=FluxLogger(level=LogLevel.ERROR))
                binary_path = compiler.compile_file(temp_file)
                
                if test_case.should_fail:
                    self.logger.error(f"COMPILER TEST FAILED: {test_case.name} - Expected failure but succeeded", "test")
                    return False
                else:
                    self.logger.info(f"COMPILER TEST PASSED: {test_case.name}", "test")
                    return True
                    
            finally:
                # Clean up temp file
                os.unlink(temp_file)
                
        except Exception as e:
            if test_case.should_fail:
                if test_case.expected_error and test_case.expected_error.lower() not in str(e).lower():
                    self.logger.warning(f"COMPILER TEST WARNING: {test_case.name} - Wrong error: {e}", "test")
                    return False
                else:
                    self.logger.info(f"COMPILER TEST PASSED: {test_case.name} - Failed as expected: {e}", "test")
                    return True
            else:
                self.logger.error(f"COMPILER TEST FAILED: {test_case.name} - Unexpected failure: {e}", "test")
                return False
    
    def run_test_case(self, test_case: FluxTestCase) -> bool:
        """Run a single test case based on its type"""
        if test_case.test_type == "lexer":
            return self.run_lexer_test(test_case)
        elif test_case.test_type == "parser":
            return self.run_parser_test(test_case)
        elif test_case.test_type == "compiler":
            return self.run_compiler_test(test_case)
        else:
            self.logger.error(f"Unknown test type: {test_case.test_type}", "test")
            return False
    
    def run_all_tests(self) -> Dict[str, Any]:
        """Run all test cases and return results"""
        results = {
            'total': len(self.test_cases),
            'passed': 0,
            'failed': 0,
            'warnings': 0,
            'by_type': {
                'lexer': {'passed': 0, 'failed': 0},
                'parser': {'passed': 0, 'failed': 0},
                'compiler': {'passed': 0, 'failed': 0}
            }
        }
        
        self.logger.section("Running Flux Failing and Edge-Case Test Suite", LogLevel.INFO, "test")
        
        for i, test_case in enumerate(self.test_cases, 1):
            self.logger.info(f"Running test {i}/{len(self.test_cases)}: {test_case.name}", "test")
            
            success = self.run_test_case(test_case)
            
            if success:
                results['passed'] += 1
                results['by_type'][test_case.test_type]['passed'] += 1
            else:
                results['failed'] += 1
                results['by_type'][test_case.test_type]['failed'] += 1
        
        return results
    
    def generate_report(self, results: Dict[str, Any]) -> str:
        """Generate a comprehensive test report"""
        report = []
        report.append("=" * 80)
        report.append("FLUX FAILING AND EDGE-CASE TEST SUITE REPORT")
        report.append("=" * 80)
        report.append("")
        
        # Overall summary
        report.append(f"Total Tests: {results['total']}")
        report.append(f"Passed: {results['passed']}")
        report.append(f"Failed: {results['failed']}")
        report.append(f"Success Rate: {(results['passed'] / results['total'] * 100):.1f}%")
        report.append("")
        
        # Breakdown by test type
        report.append("Breakdown by Test Type:")
        report.append("-" * 40)
        for test_type, counts in results['by_type'].items():
            total = counts['passed'] + counts['failed']
            if total > 0:
                success_rate = (counts['passed'] / total * 100)
                report.append(f"{test_type.capitalize():10}: {counts['passed']:3}/{total:3} ({success_rate:5.1f}%)")
        
        report.append("")
        
        # Test categories covered
        report.append("Test Categories Covered:")
        report.append("-" * 40)
        categories = set()
        for test_case in self.test_cases:
            category = test_case.name.split('_')[0]
            categories.add(category)
        
        for category in sorted(categories):
            count = sum(1 for tc in self.test_cases if tc.name.startswith(category))
            report.append(f"- {category.capitalize()}: {count} tests")
        
        report.append("")
        report.append("This test suite verifies that the Flux compiler properly handles:")
        report.append("- Lexical analysis errors (invalid tokens, unterminated literals)")
        report.append("- Syntax errors (missing semicolons, unmatched braces)")
        report.append("- Type system errors (mismatched types, undefined variables)")
        report.append("- Control flow issues (unreachable code, invalid break/continue)")
        report.append("- Edge cases (very long identifiers, many parameters)")
        report.append("- Memory management issues (null dereferencing, double free)")
        report.append("- Import and namespace problems")
        report.append("- Operator edge cases (division by zero)")
        report.append("")
        report.append("=" * 80)
        
        return "\n".join(report)


def main():
    """Main function to run the test suite"""
    suite = FluxFailingTestSuite()
    results = suite.run_all_tests()
    report = suite.generate_report(results)
    
    print("\n" + report)
    
    # Save report to file
    report_file = Path(__file__).parent / "test_report_failing_edge_cases.txt"
    with open(report_file, 'w') as f:
        f.write(report)
    
    print(f"\nDetailed report saved to: {report_file}")
    
    # Return appropriate exit code
    return 0 if results['failed'] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
