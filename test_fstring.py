#!/usr/bin/env python3

import sys
sys.path.append('src')

from compiler.fast import *
from compiler.flexer import FluxLexer
from compiler.fparser import FluxParser
from llvmlite import ir
import llvmlite.binding as llvm

# Initialize LLVM
llvm.initialize()
llvm.initialize_native_target()
llvm.initialize_native_asmprinter()

# Test f-string with string variable
test_code = '''
using standard::types;
noopstr s = "world";
noopstr result = f"Hello {s}!";
'''

print('Parsing test code...')
tokens = FluxLexer(test_code).tokenize()
ast = FluxParser(tokens).parse()

print('Generating LLVM IR...')
try:
    module = ast.codegen()
    print('Generated IR:')
    print(str(module))
except Exception as e:
    print(f'Error: {e}')
    import traceback
    traceback.print_exc()
