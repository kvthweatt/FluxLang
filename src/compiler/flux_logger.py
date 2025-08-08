#!/usr/bin/env python3
"""
Flux Compiler Logging System

Provides configurable verbose logging with multiple levels and output options.
Supports both command-line configuration and environment variables.

Copyright (C) 2025 Karac Thweatt
"""

import sys
import os
import logging
import json
from pathlib import Path
from typing import Optional, Dict, Any, TextIO
from enum import IntEnum
from datetime import datetime

class LogLevel(IntEnum):
    """Flux-specific log levels"""
    SILENT = 0      # No output except errors
    ERROR = 1       # Errors only
    WARNING = 2     # Warnings and errors
    INFO = 3        # General information
    DEBUG = 4       # Detailed debugging info
    TRACE = 5       # Maximum verbosity

class FluxLogger:
    """
    Configurable logging system for the Flux compiler
    
    Supports multiple output streams, log levels, and formatting options.
    Can be configured via command line, environment variables, or config files.
    """
    
    def __init__(self, 
                 level: int = LogLevel.INFO,
                 output_stream: Optional[TextIO] = None,
                 error_stream: Optional[TextIO] = None,
                 log_file: Optional[str] = None,
                 timestamp: bool = False,
                 colors: bool = True,
                 component_filter: Optional[list] = None):
        """
        Initialize the Flux logger
        
        Args:
            level: Logging level (0-5)
            output_stream: Stream for general output (default: sys.stdout)
            error_stream: Stream for error output (default: sys.stderr)  
            log_file: Optional file to write logs to
            timestamp: Whether to include timestamps in output
            colors: Whether to use colored output (if terminal supports it)
            component_filter: List of component names to log (None = all)
        """
        self.level = max(0, min(5, level))  # Clamp to valid range
        self.output_stream = output_stream or sys.stdout
        self.error_stream = error_stream or sys.stderr
        self.log_file_path = log_file
        self.log_file_handle: Optional[TextIO] = None
        self.timestamp = timestamp
        self.colors = colors and hasattr(sys.stdout, 'isatty') and sys.stdout.isatty()
        self.component_filter = set(component_filter) if component_filter else None
        
        # Color codes for different log levels
        self.color_codes = {
            LogLevel.ERROR: '\033[91m',    # Red
            LogLevel.WARNING: '\033[93m',  # Yellow
            LogLevel.INFO: '\033[94m',     # Blue
            LogLevel.DEBUG: '\033[95m',    # Magenta
            LogLevel.TRACE: '\033[96m',    # Cyan
        }
        self.reset_code = '\033[0m'
        
        # Open log file if specified
        if self.log_file_path:
            try:
                # Ensure log directory exists
                Path(self.log_file_path).parent.mkdir(parents=True, exist_ok=True)
                self.log_file_handle = open(self.log_file_path, 'w', encoding='utf-8')
            except Exception as e:
                self._write_error(f"Failed to open log file '{self.log_file_path}': {e}")
    
    def _should_log(self, level: int, component: Optional[str] = None) -> bool:
        """Check if a message should be logged based on level and component filter"""
        if level > self.level:
            return False
        if self.component_filter and component and component not in self.component_filter:
            return False
        return True
    
    def _format_message(self, level: int, component: Optional[str], message: str) -> str:
        """Format a log message with optional timestamp and component info"""
        parts = []
        
        if self.timestamp:
            timestamp = datetime.now().strftime('%H:%M:%S.%f')[:-3]  # millisecond precision
            parts.append(f"[{timestamp}]")
        
        # Add level indicator
        level_names = {
            LogLevel.SILENT: "",
            LogLevel.ERROR: "ERROR",
            LogLevel.WARNING: "WARN",
            LogLevel.INFO: "INFO", 
            LogLevel.DEBUG: "DEBUG",
            LogLevel.TRACE: "TRACE"
        }
        level_name = level_names.get(level, f"L{level}")
        if level_name:
            parts.append(f"[{level_name}]")
        
        if component:
            parts.append(f"[{component}]")
        
        parts.append(message)
        return " ".join(parts)
    
    def _write_message(self, level: int, component: Optional[str], message: str):
        """Write a formatted message to appropriate streams"""
        if not self._should_log(level, component):
            return
            
        formatted_msg = self._format_message(level, component, message)
        
        # Choose output stream
        stream = self.error_stream if level <= LogLevel.WARNING else self.output_stream
        
        # Apply color if enabled
        if self.colors and level in self.color_codes:
            colored_msg = f"{self.color_codes[level]}{formatted_msg}{self.reset_code}"
            stream.write(colored_msg + "\n")
        else:
            stream.write(formatted_msg + "\n")
        
        stream.flush()
        
        # Also write to log file if specified (without colors)
        if self.log_file_handle:
            self.log_file_handle.write(formatted_msg + "\n")
            self.log_file_handle.flush()
    
    def _write_error(self, message: str):
        """Write an error message directly to stderr (bypasses filtering)"""
        self.error_stream.write(f"FLUX LOGGER ERROR: {message}\n")
        self.error_stream.flush()
    
    # Public logging methods
    def error(self, message: str, component: Optional[str] = None):
        """Log an error message"""
        self._write_message(LogLevel.ERROR, component, message)
    
    def warning(self, message: str, component: Optional[str] = None):
        """Log a warning message"""
        self._write_message(LogLevel.WARNING, component, message)
    
    def info(self, message: str, component: Optional[str] = None):
        """Log an informational message"""
        self._write_message(LogLevel.INFO, component, message)
    
    def debug(self, message: str, component: Optional[str] = None):
        """Log a debug message"""
        self._write_message(LogLevel.DEBUG, component, message)
    
    def trace(self, message: str, component: Optional[str] = None):
        """Log a trace message (maximum verbosity)"""
        self._write_message(LogLevel.TRACE, component, message)
    
    def log_data(self, level: int, title: str, data: Any, component: Optional[str] = None):
        """Log structured data (tokens, AST, etc.) with proper formatting"""
        if not self._should_log(level, component):
            return
            
        self._write_message(level, component, f"{title}:")
        
        # Format data based on type
        if isinstance(data, (list, tuple)):
            for i, item in enumerate(data):
                self._write_message(level, component, f"  [{i}] {item}")
        elif isinstance(data, dict):
            for key, value in data.items():
                self._write_message(level, component, f"  {key}: {value}")
        elif isinstance(data, str):
            # Multi-line string - print each line with indentation
            for line in data.splitlines():
                self._write_message(level, component, f"  {line}")
        else:
            # Single object - convert to string
            self._write_message(level, component, f"  {data}")
    
    def section(self, title: str, level: int = LogLevel.INFO, component: Optional[str] = None):
        """Log a section header for better organization"""
        if not self._should_log(level, component):
            return
        border = "=" * min(50, len(title) + 4)
        self._write_message(level, component, border)
        self._write_message(level, component, f"  {title}")  
        self._write_message(level, component, border)
    
    def step(self, step_name: str, level: int = LogLevel.INFO, component: Optional[str] = None):
        """Log a compilation step"""
        self._write_message(level, component, f"► {step_name}")
    
    def success(self, message: str, component: Optional[str] = None):
        """Log a success message"""
        if self.colors:
            green = '\033[92m'
            formatted_msg = f"{green}✓ {message}{self.reset_code}"
            self.output_stream.write(formatted_msg + "\n")
        else:
            self._write_message(LogLevel.INFO, component, f"✓ {message}")
    
    def failure(self, message: str, component: Optional[str] = None):
        """Log a failure message"""  
        if self.colors:
            red = '\033[91m'
            formatted_msg = f"{red}✗ {message}{self.reset_code}"
            self.error_stream.write(formatted_msg + "\n")
        else:
            self._write_message(LogLevel.ERROR, component, f"✗ {message}")
    
    def set_level(self, level: int):
        """Change the logging level at runtime"""
        self.level = max(0, min(5, level))
    
    def set_component_filter(self, components: Optional[list]):
        """Change the component filter at runtime"""
        self.component_filter = set(components) if components else None
    
    def close(self):
        """Close log file handle if open"""
        if self.log_file_handle:
            self.log_file_handle.close()
            self.log_file_handle = None
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


class FluxLoggerConfig:
    """
    Configuration helper for FluxLogger
    
    Supports loading configuration from:
    1. Command line arguments
    2. Environment variables  
    3. Configuration files (JSON)
    4. Default values
    """
    
    @staticmethod
    def from_args(args: Dict[str, Any]) -> Dict[str, Any]:
        """Create logger config from command line arguments"""
        config = {}
        
        # Map common argument patterns
        if 'verbosity' in args or 'verbose' in args or 'v' in args:
            config['level'] = args.get('verbosity') or args.get('verbose') or args.get('v')
        
        if 'log_file' in args or 'logfile' in args:
            config['log_file'] = args.get('log_file') or args.get('logfile')
            
        if 'timestamp' in args or 'timestamps' in args:
            config['timestamp'] = args.get('timestamp') or args.get('timestamps')
            
        if 'no_color' in args or 'no_colors' in args:
            config['colors'] = not (args.get('no_color') or args.get('no_colors'))
            
        if 'components' in args or 'filter' in args:
            components = args.get('components') or args.get('filter')
            if isinstance(components, str):
                config['component_filter'] = [c.strip() for c in components.split(',')]
            elif isinstance(components, list):
                config['component_filter'] = components
        
        return config
    
    @staticmethod
    def from_env() -> Dict[str, Any]:
        """Create logger config from environment variables"""
        config = {}
        
        # Check for Flux-specific environment variables
        if 'FLUX_LOG_LEVEL' in os.environ:
            try:
                config['level'] = int(os.environ['FLUX_LOG_LEVEL'])
            except ValueError:
                pass
        
        if 'FLUX_LOG_FILE' in os.environ:
            config['log_file'] = os.environ['FLUX_LOG_FILE']
            
        if 'FLUX_LOG_TIMESTAMP' in os.environ:
            config['timestamp'] = os.environ['FLUX_LOG_TIMESTAMP'].lower() in ('1', 'true', 'yes')
            
        if 'FLUX_LOG_NO_COLOR' in os.environ:
            config['colors'] = os.environ['FLUX_LOG_NO_COLOR'].lower() not in ('1', 'true', 'yes')
            
        if 'FLUX_LOG_COMPONENTS' in os.environ:
            components = os.environ['FLUX_LOG_COMPONENTS']
            config['component_filter'] = [c.strip() for c in components.split(',')]
        
        return config
    
    @staticmethod
    def from_file(config_path: str) -> Dict[str, Any]:
        """Create logger config from JSON configuration file"""
        try:
            with open(config_path, 'r') as f:
                data = json.load(f)
            return data.get('logging', {})
        except Exception:
            return {}
    
    @staticmethod
    def create_logger(**overrides) -> FluxLogger:
        """
        Create a FluxLogger with configuration from multiple sources
        
        Priority order:
        1. Function arguments (overrides)
        2. Environment variables
        3. Default values
        """
        config = {}
        
        # Load from environment
        config.update(FluxLoggerConfig.from_env())
        
        # Apply overrides
        config.update(overrides)
        
        return FluxLogger(**config)


# Default global logger instance
_default_logger: Optional[FluxLogger] = None

def get_default_logger() -> FluxLogger:
    """Get or create the default global logger"""
    global _default_logger
    if _default_logger is None:
        _default_logger = FluxLoggerConfig.create_logger()
    return _default_logger

def set_default_logger(logger: FluxLogger):
    """Set the default global logger"""
    global _default_logger
    _default_logger = logger

# Convenience functions using the default logger
def error(message: str, component: Optional[str] = None):
    get_default_logger().error(message, component)

def warning(message: str, component: Optional[str] = None):
    get_default_logger().warning(message, component)

def info(message: str, component: Optional[str] = None):
    get_default_logger().info(message, component)

def debug(message: str, component: Optional[str] = None):
    get_default_logger().debug(message, component)

def trace(message: str, component: Optional[str] = None):
    get_default_logger().trace(message, component)

def log_data(level: int, title: str, data: Any, component: Optional[str] = None):
    get_default_logger().log_data(level, title, data, component)

def section(title: str, level: int = LogLevel.INFO, component: Optional[str] = None):
    get_default_logger().section(title, level, component)

def step(step_name: str, level: int = LogLevel.INFO, component: Optional[str] = None):
    get_default_logger().step(step_name, level, component)

def success(message: str, component: Optional[str] = None):
    get_default_logger().success(message, component)

def failure(message: str, component: Optional[str] = None):
    get_default_logger().failure(message, component)
