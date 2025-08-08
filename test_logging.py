#!/usr/bin/env python3
"""
Test script to demonstrate the Flux logging system capabilities
"""

import sys
import os
from pathlib import Path

# Add src/compiler to Python path
sys.path.insert(0, str(Path(__file__).parent / "src" / "compiler"))

from flux_logger import FluxLogger, FluxLoggerConfig, LogLevel

def test_basic_logging():
    """Test basic logging functionality"""
    print("=" * 50)
    print("Testing Basic Logging")
    print("=" * 50)
    
    logger = FluxLogger(level=LogLevel.INFO, colors=True)
    
    logger.info("This is an info message")
    logger.warning("This is a warning message")
    logger.error("This is an error message")
    logger.debug("This debug message should not appear")
    logger.trace("This trace message should not appear")
    
    print()

def test_component_filtering():
    """Test component-based filtering"""
    print("=" * 50)
    print("Testing Component Filtering")
    print("=" * 50)
    
    logger = FluxLogger(
        level=LogLevel.DEBUG, 
        component_filter=['lexer', 'parser'],
        colors=True
    )
    
    logger.debug("Lexer message - should appear", "lexer")
    logger.debug("Parser message - should appear", "parser")
    logger.debug("Compiler message - should NOT appear", "compiler")
    logger.info("Codegen message - should NOT appear", "codegen")
    
    print()

def test_structured_data():
    """Test structured data logging"""
    print("=" * 50)
    print("Testing Structured Data Logging")
    print("=" * 50)
    
    logger = FluxLogger(level=LogLevel.DEBUG, colors=True)
    
    # Test with list
    tokens = ["TOKEN_IMPORT", "TOKEN_STRING", "TOKEN_SEMICOLON"]
    logger.log_data(LogLevel.DEBUG, "Sample Tokens", tokens, "lexer")
    
    # Test with dict
    ast_data = {"type": "Program", "children": 3, "location": "line 1"}
    logger.log_data(LogLevel.DEBUG, "AST Node", ast_data, "parser")
    
    # Test with multiline string
    llvm_ir = """define i32 @main() {
entry:
  ret i32 0
}"""
    logger.log_data(LogLevel.DEBUG, "LLVM IR", llvm_ir, "codegen")
    
    print()

def test_timestamped_logging():
    """Test logging with timestamps"""
    print("=" * 50)
    print("Testing Timestamped Logging")
    print("=" * 50)
    
    logger = FluxLogger(level=LogLevel.INFO, timestamp=True, colors=True)
    
    logger.info("Starting compilation process")
    logger.step("Lexical analysis", LogLevel.INFO, "lexer")
    logger.step("Parsing", LogLevel.INFO, "parser")
    logger.success("Compilation completed successfully")
    
    print()

def test_log_levels():
    """Test all log levels"""
    print("=" * 50)
    print("Testing All Log Levels")
    print("=" * 50)
    
    for level in range(6):
        print(f"\n--- Log Level {level} ---")
        logger = FluxLogger(level=level, colors=True)
        
        logger.error("Error message", "test")
        logger.warning("Warning message", "test") 
        logger.info("Info message", "test")
        logger.debug("Debug message", "test")
        logger.trace("Trace message", "test")

def test_file_logging():
    """Test logging to file"""
    print("=" * 50)
    print("Testing File Logging")
    print("=" * 50)
    
    log_file = "test_log.txt"
    
    # Clean up any existing log file
    if os.path.exists(log_file):
        os.remove(log_file)
    
    with FluxLogger(level=LogLevel.DEBUG, log_file=log_file, colors=True) as logger:
        logger.info("This message goes to both console and file")
        logger.debug("Debug information", "test")
        logger.section("Test Section", LogLevel.INFO, "test")
    
    # Show file contents
    if os.path.exists(log_file):
        print(f"\nContents of {log_file}:")
        with open(log_file, 'r') as f:
            print(f.read())
        os.remove(log_file)  # Cleanup
    
    print()

def test_environment_config():
    """Test environment variable configuration"""
    print("=" * 50)
    print("Testing Environment Configuration")
    print("=" * 50)
    
    # Set some environment variables
    os.environ['FLUX_LOG_LEVEL'] = '4'
    os.environ['FLUX_LOG_TIMESTAMP'] = 'true'
    os.environ['FLUX_LOG_COMPONENTS'] = 'test,demo'
    
    logger = FluxLoggerConfig.create_logger()
    
    print(f"Logger level from environment: {logger.level}")
    print(f"Timestamp enabled: {logger.timestamp}")
    print(f"Component filter: {logger.component_filter}")
    
    logger.debug("This should appear", "test")
    logger.debug("This should also appear", "demo")
    logger.debug("This should NOT appear", "other")
    
    # Cleanup environment
    del os.environ['FLUX_LOG_LEVEL']
    del os.environ['FLUX_LOG_TIMESTAMP']
    del os.environ['FLUX_LOG_COMPONENTS']
    
    print()

def demo_compilation_style():
    """Demo compilation-style logging output"""
    print("=" * 50)
    print("Demo: Compilation-Style Output")
    print("=" * 50)
    
    logger = FluxLogger(level=LogLevel.INFO, colors=True)
    
    logger.section("Compiling hello.fx", LogLevel.INFO)
    
    logger.step("Reading source file", LogLevel.INFO, "compiler")
    logger.debug("Read 156 characters from hello.fx", "compiler")
    
    logger.step("Lexical analysis", LogLevel.INFO, "lexer")
    logger.debug("Generated 23 tokens", "lexer")
    
    logger.step("Parsing", LogLevel.INFO, "parser")
    logger.debug("AST generation completed", "parser")
    
    logger.step("LLVM IR code generation", LogLevel.INFO, "codegen")
    logger.debug("Generated LLVM IR (245 chars)", "codegen")
    
    logger.step("Compiling to object file (Windows)", LogLevel.INFO, "llc")
    logger.debug("Running: llc -O2 -filetype=obj hello.ll -o hello.obj", "llc")
    
    logger.step("Linking executable: hello.exe", LogLevel.INFO, "linker")
    logger.debug("Running: gcc -no-pie hello.obj -o hello.exe", "linker")
    
    logger.success("Compilation completed: hello.exe")
    
    print()

if __name__ == "__main__":
    print("Flux Logging System Test Suite")
    print("==============================")
    print()
    
    test_basic_logging()
    test_component_filtering()
    test_structured_data()
    test_timestamped_logging()
    test_log_levels()
    test_file_logging()
    test_environment_config()
    demo_compilation_style()
    
    print("All tests completed!")
