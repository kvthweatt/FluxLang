root dir
|
|-- build\              // all programs build here: build\program\program.ll IR output
|-- build\tmp.fx        // Preprocessor temporary output for builds
|-- config\             // All configuration
|-- config\flux_configuration.cfg // Compiler configuration
|-- docs\               // All docoumentation
|-- examples\           // Battle-tested production ready working examples
|-- scripts\            // Scripts like run_tests.py, compiles all test files in tests\
|-- tests\              // All Flux source file (.fx) testing (weird_test.fx, 64bit_test.fx)
|-- src\                // Compiler & Standard Library source
|-- src\stdlib\         // Standard Library source
|-- src\compiler\       // Compiler source
|   `--> fpreprocess.py // Preprocessor
|   `--> flexer.py      // Lexer
|   `--> fparser.py     // Parser
	`--> futilities.py  // Utility functions
	`--> ftypesys.py    // Type System
	`--> flogger.py     // Logging
	`--> fconfig.py     // Config helper
|   `--> fast.py        // AST
|   `--> fc.py          // Compiler front-end
|
`--> fc.py              // Compiler front-end entrypoint, root, calls to fc.py in src\compiler\