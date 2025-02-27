#include "include/interpreter.h"
#include "include/ast.h"
#include <sstream>
#include <iostream>

namespace flux {

// InterpreterError implementation
InterpreterError::InterpreterError(const std::string& message)
    : std::runtime_error(message) {}

// Value implementation
std::string Value::toString() const {
    if (isVoid()) return "void";
    if (isInteger()) return std::to_string(as<int64_t>());
    if (isFloat()) return std::to_string(as<double>());
    if (isBoolean()) return as<bool>() ? "true" : "false";
    if (isCharacter()) return std::string(1, as<char>());
    if (isString()) return as<std::string>();
    
    if (isArray()) {
        const auto& array = as<std::vector<Value>>();
        std::ostringstream oss;
        oss << "[";
        for (size_t i = 0; i < array.size(); ++i) {
            oss << array[i].toString();
            if (i < array.size() - 1) oss << ", ";
        }
        oss << "]";
        return oss.str();
    }
    
    if (isObject()) {
        const auto& obj = as<std::unordered_map<std::string, Value>>();
        std::ostringstream oss;
        oss << "{";
        bool first = true;
        for (const auto& [key, value] : obj) {
            if (!first) oss << ", ";
            oss << key << ": " << value.toString();
            first = false;
        }
        oss << "}";
        return oss.str();
    }
    
    if (isCallable()) return "<function>";
    
    return "<unknown>";
}

// Function implementation
Function::Function(std::shared_ptr<FunctionDeclaration> declaration, std::shared_ptr<Environment> closure)
    : declaration(declaration), closure(closure) {
}

Value Function::call(Interpreter& interpreter, const std::vector<Value>& args) {    
    // Create a new environment for function execution
    auto environment = std::make_shared<Environment>(closure);
    
    // Bind parameters to arguments
    const auto& params = declaration->getParams();
    for (size_t i = 0; i < params.size(); ++i) {
        environment->define(params[i].getName(), args[i]);
    }
    
    try {
        // Execute function body
        interpreter.executeBlock(declaration->getBody(), environment);
        return Value(); // Return void by default
    } catch (const Interpreter::ReturnValue& returnValue) {
        // Handle return statement
        return returnValue.value;
    }
}

int Function::arity() const {
    return static_cast<int>(declaration->getParams().size());
}

// BuiltinFunction implementation
BuiltinFunction::BuiltinFunction(
    std::string name, 
    int arity, 
    std::function<Value(Interpreter&, const std::vector<Value>&)> function
) : name(std::move(name)), 
    functionArity(arity), 
    function(std::move(function)) {}

Value BuiltinFunction::call(Interpreter& interpreter, const std::vector<Value>& args) {
    return function(interpreter, args);
}

int BuiltinFunction::arity() const {
    return functionArity;
}

// Environment implementation
Environment::Environment() : enclosing(nullptr) {}

Environment::Environment(std::shared_ptr<Environment> enclosingEnv) 
    : enclosing(enclosingEnv) {}

void Environment::define(const std::string& name, const Value& value) {
    values[name] = value;
}

Value Environment::get(const std::string& name) {
    auto it = values.find(name);
    if (it != values.end()) {
        return it->second;
    }
    
    if (enclosing) {
        return enclosing->get(name);
    }
    
    throw InterpreterError("Undefined variable '" + name + "'.");
}

void Environment::assign(const std::string& name, const Value& value) {
    auto it = values.find(name);
    if (it != values.end()) {
        it->second = value;
        return;
    }
    
    if (enclosing) {
        enclosing->assign(name, value);
        return;
    }
    
    throw InterpreterError("Undefined variable '" + name + "'.");
}

void Environment::printSymbols() {
    std::cout << "Environment Symbols:" << std::endl;
    for (const auto& [name, value] : values) {
        std::cout << name << ": " << value.toString() << std::endl;
    }
    
    if (enclosing) {
        std::cout << "--- Enclosing Environment ---" << std::endl;
        enclosing->printSymbols();
    }
}

// Interpreter implementation
Interpreter::Interpreter() {
    globals = std::make_shared<Environment>();
    environment = globals;
    
    defineBuiltins();
}

void Interpreter::defineBuiltins() {
    // Define print function
    auto printFunction = std::make_shared<BuiltinFunction>(
        "print", 
        -1, // Variable arity
        [this](Interpreter&, const std::vector<Value>& args) -> Value {
            return this->print(args);
        }
    );
    globals->define("print", Value(printFunction));
    
    // Define input function
    auto inputFunction = std::make_shared<BuiltinFunction>(
        "input", 
        -1, // Variable arity
        [this](Interpreter&, const std::vector<Value>& args) -> Value {
            return this->input(args);
        }
    );
    globals->define("input", Value(inputFunction));
}

void Interpreter::printGlobalSymbols() {
    std::cout << "Global Symbols:" << std::endl;
    globals->printSymbols();
}

Value Interpreter::print(const std::vector<Value>& args) {
    if (args.empty()) {
        throw InterpreterError("print requires at least one argument");
    }

    std::string output;
    for (size_t i = 0; i < args.size(); ++i) {
        output += args[i].toString();
        if (i < args.size() - 1) output += " ";
    }
    std::cout << output;
    
    // Return the last argument
    return args.back();
}

Value Interpreter::input(const std::vector<Value>& args) {
    // Print prompt if provided
    if (!args.empty()) {
        std::cout << args[0].toString();
    }
    
    std::string input;
    std::getline(std::cin, input);
    return Value(input);
}

bool Interpreter::isTruthy(const Value& value) {
    if (value.isVoid()) return false;
    if (value.isBoolean()) return value.as<bool>();
    if (value.isInteger()) return value.as<int64_t>() != 0;
    if (value.isFloat()) return value.as<double>() != 0.0;
    if (value.isString()) return !value.as<std::string>().empty();
    if (value.isArray()) return !value.as<std::vector<Value>>().empty();
    return true;
}

bool Interpreter::isEqual(const Value& a, const Value& b) {
    // Handle null/void equality
    if (a.isVoid() && b.isVoid()) return true;
    if (a.isVoid() || b.isVoid()) return false;
    
    // Handle type-specific equality
    if (a.isInteger() && b.isInteger()) {
        return a.as<int64_t>() == b.as<int64_t>();
    }
    
    if (a.isFloat() && b.isFloat()) {
        return a.as<double>() == b.as<double>();
    }
    
    // Handle mixed numeric types
    if (a.isNumber() && b.isNumber()) {
        double aVal = a.isFloat() ? a.as<double>() : static_cast<double>(a.as<int64_t>());
        double bVal = b.isFloat() ? b.as<double>() : static_cast<double>(b.as<int64_t>());
        return aVal == bVal;
    }
    
    if (a.isBoolean() && b.isBoolean()) {
        return a.as<bool>() == b.as<bool>();
    }
    
    if (a.isCharacter() && b.isCharacter()) {
        return a.as<char>() == b.as<char>();
    }
    
    if (a.isString() && b.isString()) {
        return a.as<std::string>() == b.as<std::string>();
    }
    
    // Different types are not equal
    return false;
}

Value Interpreter::execute(std::shared_ptr<Program> program) {
    try {
        const auto& declarations = program->getDeclarations();
        
        std::cout << "Total Declarations: " << declarations.size() << std::endl;
        
        // Extensive logging for declarations
        std::cout << "=== Detailed Declaration Logging ===" << std::endl;
        for (const auto& decl : declarations) {
            if (auto funcDecl = std::dynamic_pointer_cast<FunctionDeclaration>(decl)) {
                std::cout << "Function Declaration Found:" << std::endl;
                std::cout << "  Name: " << funcDecl->getName() << std::endl;
                std::cout << "  Return Type: " << funcDecl->getReturnType()->toString() << std::endl;
                std::cout << "  Parameters: " << funcDecl->getParams().size() << std::endl;
                std::cout << "  Has Body: " << (funcDecl->getBody() != nullptr) << std::endl;
            } else if (auto classDecl = std::dynamic_pointer_cast<ClassDeclaration>(decl)) {
                std::cout << "Class Declaration Found:" << std::endl;
                std::cout << "  Name: " << classDecl->getName() << std::endl;
                std::cout << "  Members: " << classDecl->getMembers().size() << std::endl;
            } else {
                std::cout << "Other Declaration: " << decl->getName() << "\n\n";
            }
        }
        
        // First pass: Process namespace, class and function declarations
        for (const auto& decl : declarations) {
            if (auto namespaceDecl = std::dynamic_pointer_cast<NamespaceDeclaration>(decl)) {
                // Register namespace in globals
                executeNamespaceDeclaration(namespaceDecl);
            } else if (auto classDecl = std::dynamic_pointer_cast<ClassDeclaration>(decl)) {
                // Register class in globals
                executeClassDeclaration(classDecl);
            } else if (auto objDecl = std::dynamic_pointer_cast<ObjectDeclaration>(decl)) {
                // Register object in globals
                executeObjectDeclaration(objDecl);
            } else if (auto structDecl = std::dynamic_pointer_cast<StructDeclaration>(decl)) {
                // Register struct in globals
                executeStructDeclaration(structDecl);
            } else if (auto funcDecl = std::dynamic_pointer_cast<FunctionDeclaration>(decl)) {
                // Create function object
                auto function = std::make_shared<Function>(funcDecl, environment);
                
                // Register function in global scope
                globals->define(funcDecl->getName(), Value(function));
            }
        }
        
        // Look for main function and execute it
        try {
            // Print all global symbols for comprehensive debugging
            //std::cout << "\n=== Global Symbols Before Execution ===" << std::endl;
            //printGlobalSymbols();
            //std::cout << "=====================================" << "\n\n";
            
            // Try to get the main function
            Value mainFunc = globals->get("main");
            
            if (mainFunc.isCallable()) {                
                // Empty vector for main() arguments
                std::vector<Value> args;
                
                try {
                    std::cout << "[Result]\n\n";
                    Value result = mainFunc.as<std::shared_ptr<Callable>>()->call(*this, args);
                    if (result.toString() != "0") {
                        std::cout << "\nMain function returned error: " << result.toString() << std::endl;
                        return result;
                    }
                    std::cout << "Main function returned success: " << result.toString() << std::endl;
                    return result;
                }
                catch (const ReturnValue& returnValue) {
                    std::cout << "\nMain function executed with return value: " << returnValue.value.toString() << std::endl;
                    return returnValue.value;
                }
                catch (const std::exception& e) {
                    std::cerr << "\nException while executing main function: " << e.what() << std::endl;
                    return Value(-1);
                }
            } else {
                std::cout << "\nMain function is NOT callable" << std::endl;
                return Value(-1); // Return -1 if main is not callable
            }
        } catch (const InterpreterError& e) {
            std::cerr << "Error locating main function: " << e.what() << std::endl;
            std::cerr << "Available global symbols:" << std::endl;
            printGlobalSymbols();
            return Value(-1); // Return error code
        }
    } catch (const InterpreterError& error) {
        std::cerr << "Runtime Error: " << error.what() << std::endl;
        return Value(-1); // Return error code
    }
}

void Interpreter::execute(std::shared_ptr<Statement> stmt) {
    if (auto exprStmt = std::dynamic_pointer_cast<ExpressionStatement>(stmt)) {
        auto expr = exprStmt->getExpr();
        
        if (auto identExpr = std::dynamic_pointer_cast<IdentifierExpression>(expr)) {
            std::string name = identExpr->getName();
            
            try {
                Value structValue = globals->get(name);
                
                if (structValue.isObject()) {
                    globals->define(name, structValue);
                    return;
                }
            } catch (const InterpreterError&) {}
        }
        
        evaluate(expr);
        return;
    }
    
    if (auto blockStmt = std::dynamic_pointer_cast<BlockStatement>(stmt)) {
        executeBlock(stmt, std::make_shared<Environment>(environment));
        return;
    }
    
    if (auto ifStmt = std::dynamic_pointer_cast<IfStatement>(stmt)) {
        executeIf(stmt);
        return;
    }
    
    if (auto whileStmt = std::dynamic_pointer_cast<WhileStatement>(stmt)) {
        executeWhile(stmt);
        return;
    }
    
    if (auto forStmt = std::dynamic_pointer_cast<ForStatement>(stmt)) {
        executeFor(stmt);
        return;
    }
    
    if (auto returnStmt = std::dynamic_pointer_cast<ReturnStatement>(stmt)) {
        executeReturn(stmt);
        return;
    }
    
    if (auto varDeclStmt = std::dynamic_pointer_cast<VariableDeclaration>(stmt)) {
        executeVariableDeclaration(stmt);
        return;
    }
    
    if (auto structDeclStmt = std::dynamic_pointer_cast<StructDeclaration>(stmt)) {
        executeStructDeclaration(structDeclStmt);
        return;
    }
}

void Interpreter::executeDeclaration(std::shared_ptr<Declaration> decl) {
    // Handle function declarations
    if (auto funcDecl = std::dynamic_pointer_cast<FunctionDeclaration>(decl)) {
        // Create function object
        auto function = std::make_shared<Function>(funcDecl, environment);
        
        // Define function in current environment
        environment->define(funcDecl->getName(), Value(function));
    }
    // Handle variable declarations
    else if (auto varDecl = std::dynamic_pointer_cast<VariableDeclaration>(decl)) {
        // Evaluate initializer if present
        Value value;
        if (varDecl->getInitializer()) {
            value = evaluate(varDecl->getInitializer());
        }
        
        // Define variable in current environment
        environment->define(varDecl->getName(), value);
    }
    // Handle namespace declarations
    else if (auto namespaceDecl = std::dynamic_pointer_cast<NamespaceDeclaration>(decl)) {
        executeNamespaceDeclaration(namespaceDecl);
    }
    // Handle class declarations
    else if (auto classDecl = std::dynamic_pointer_cast<ClassDeclaration>(decl)) {
        executeClassDeclaration(classDecl);
    }
    // Handle struct declarations
    else if (auto structDecl = std::dynamic_pointer_cast<StructDeclaration>(decl)) {
        executeStructDeclaration(structDecl);
    }
    // Handle object declarations
    else if (auto objDecl = std::dynamic_pointer_cast<ObjectDeclaration>(decl)) {
        executeObjectDeclaration(objDecl);
    }
    // Handle import declarations
    else if (auto importDecl = std::dynamic_pointer_cast<ImportDeclaration>(decl)) {
        // TODO: Implement import handling
        std::cout << "Import of " << importDecl->getPath() << " not yet implemented" << std::endl;
    }
}

void Interpreter::executeBlock(std::shared_ptr<Statement> blockStmt, std::shared_ptr<Environment> env) {
    auto block = std::dynamic_pointer_cast<BlockStatement>(blockStmt);
    if (!block) {
        std::cerr << "executeBlock called with non-block statement" << std::endl;
        return;
    }

    auto previous = environment;
    
    try {
        environment = env;
        
        for (const auto& statement : block->getStatements()) {
            if (!statement) {
                std::cerr << "Null statement in block" << std::endl;
                continue;
            }
            
            // Explicit handling for variable declarations
            if (auto varDecl = std::dynamic_pointer_cast<VariableDeclaration>(statement)) {
                std::string varName = varDecl->getName();
                Value value;
                
                if (varDecl->getInitializer()) {
                    value = evaluate(varDecl->getInitializer());
                }
                
                environment->define(varName, value);
            } 
            // Explicit handling for struct declarations within functions
            else if (auto structDecl = std::dynamic_pointer_cast<StructDeclaration>(statement)) {
                std::string structName = structDecl->getName();
                
                std::unordered_map<std::string, Value> structTemplate;
                
                for (const auto& field : structDecl->getFields()) {
                    Value fieldValue;
                    if (field.getInitializer()) {
                        fieldValue = evaluate(field.getInitializer());
                    }
                    
                    structTemplate[field.getName()] = fieldValue;
                }
                
                // Define the struct in the current environment
                environment->define(structName, Value(structTemplate));
            } 
            else {
                execute(statement);
            }
        }
    } catch (const ReturnValue& returnValue) {
        environment = previous;
        throw;
    } catch (const std::exception& e) {
        std::cerr << "Exception during block execution: " << e.what() << std::endl;
        environment = previous;
        throw;
    }
    
    environment = previous;
}

void Interpreter::executeExpression(std::shared_ptr<Statement> stmt) {
    auto exprStmt = std::dynamic_pointer_cast<ExpressionStatement>(stmt);
    if (exprStmt) {
        evaluate(exprStmt->getExpr());
    }
}

void Interpreter::executeIf(std::shared_ptr<Statement> stmt) {
    auto ifStmt = std::dynamic_pointer_cast<IfStatement>(stmt);
    if (!ifStmt) return;

    Value condition = evaluate(ifStmt->getCondition());
    
    if (isTruthy(condition)) {
        execute(ifStmt->getThenBranch());
    } else if (ifStmt->getElseBranch()) {
        execute(ifStmt->getElseBranch());
    }
}

void Interpreter::executeWhile(std::shared_ptr<Statement> stmt) {
    auto whileStmt = std::dynamic_pointer_cast<WhileStatement>(stmt);
    if (!whileStmt) return;

    while (true) {
        Value condition = evaluate(whileStmt->getCondition());
        if (!isTruthy(condition)) break;
        
        execute(whileStmt->getBody());
    }
}

void Interpreter::executeFor(std::shared_ptr<Statement> stmt) {
    auto forStmt = std::dynamic_pointer_cast<ForStatement>(stmt);
    if (!forStmt) return;

    // Create a new environment for the for loop
    auto loopEnv = std::make_shared<Environment>(environment);
    
    // Save the current environment
    auto previous = environment;
    environment = loopEnv;
    
    try {
        // Execute initializer if present
        if (forStmt->getInit()) {
            execute(forStmt->getInit());
        }
        
        // Execute loop condition and body
        while (true) {
            // Check condition if present
            if (forStmt->getCondition()) {
                Value condition = evaluate(forStmt->getCondition());
                if (!isTruthy(condition)) break;
            }
            
            // Execute loop body
            execute(forStmt->getBody());
            
            // Execute increment if present
            if (forStmt->getUpdate()) {
                evaluate(forStmt->getUpdate());
            }
        }
    } catch (...) {
        // Restore environment even if an exception occurs
        environment = previous;
        throw;
    }
    
    // Restore the previous environment
    environment = previous;
}

void Interpreter::executeReturn(std::shared_ptr<Statement> stmt) {
    auto returnStmt = std::dynamic_pointer_cast<ReturnStatement>(stmt);
    if (!returnStmt) return;

    Value value;
    if (returnStmt->getValue()) {
        value = evaluate(returnStmt->getValue());
    }
    
    // Use exception for non-local return
    throw ReturnValue{value};
}

void Interpreter::executeVariableDeclaration(std::shared_ptr<Statement> stmt) {
    auto varDecl = std::dynamic_pointer_cast<VariableDeclaration>(stmt);
    if (!varDecl) return;

    std::string varName = varDecl->getName();
    Value value;

    // Evaluate initializer if present
    if (varDecl->getInitializer()) {
        value = evaluate(varDecl->getInitializer());
    }
    
    // Define the variable in the current environment
    environment->define(varName, value);
}

void Interpreter::executeFunctionDeclaration(std::shared_ptr<Statement> stmt) {
    // Convert the statement back to a function declaration
    auto funcDecl = std::dynamic_pointer_cast<FunctionDeclaration>(stmt);
    if (!funcDecl) return;

    auto function = std::make_shared<Function>(funcDecl, environment);
    environment->define(funcDecl->getName(), Value(function));
}

Value Interpreter::evaluate(std::shared_ptr<Expression> expr) {
    // Literal expressions
    if (auto literal = std::dynamic_pointer_cast<LiteralExpression>(expr)) {
        return evaluateLiteral(expr);
    }
    
    // Identifier expressions
    if (auto identifier = std::dynamic_pointer_cast<IdentifierExpression>(expr)) {
        return evaluateIdentifier(expr);
    }
    
    // Object instantiation expressions
    if (auto objInst = std::dynamic_pointer_cast<ObjectInstantiationExpression>(expr)) {
        return evaluateObjectInstantiation(expr);
    }
    
    // Array literal expressions
    if (auto arrayLiteral = std::dynamic_pointer_cast<ArrayLiteralExpression>(expr)) {
        return evaluateArray(expr);
    }
    
    // Scope resolution expressions
    if (auto scopeResolution = std::dynamic_pointer_cast<ScopeResolutionExpression>(expr)) {
        return evaluateScopeResolution(expr);
    }
    
    // Unary expressions
    if (auto unary = std::dynamic_pointer_cast<UnaryExpression>(expr)) {
        return evaluateUnary(expr);
    }
    
    // Binary expressions
    if (auto binary = std::dynamic_pointer_cast<BinaryExpression>(expr)) {
        return evaluateBinary(expr);
    }
    
    // Call expressions
    if (auto call = std::dynamic_pointer_cast<CallExpression>(expr)) {
        return evaluateCall(expr);
    }
    
    // Member access expressions
    if (auto memberAccess = std::dynamic_pointer_cast<MemberAccessExpression>(expr)) {
        return evaluateMemberAccess(expr);
    }
    
    // Index expressions
    if (auto index = std::dynamic_pointer_cast<IndexExpression>(expr)) {
        return evaluateIndex(expr);
    }
    
    // Injectable string expressions
    if (auto injectableExpr = std::dynamic_pointer_cast<InjectableStringExpression>(expr)) {
        return evaluateInjectableString(expr);
    }
    
    // Builtin call expressions
    if (auto builtinCall = std::dynamic_pointer_cast<BuiltinCallExpression>(expr)) {
        // Evaluate all arguments
        std::vector<Value> args;
        for (const auto& arg : builtinCall->getArgs()) {
            args.push_back(evaluate(arg));
        }
        
        // Handle specific builtin functions
        switch (builtinCall->getBuiltinType()) {
            case BuiltinCallExpression::BuiltinType::PRINT:
                return print(args);
            
            case BuiltinCallExpression::BuiltinType::INPUT:
                return input(args);
                
            case BuiltinCallExpression::BuiltinType::OPEN:
                // Placeholder implementation
                std::cout << "File opening not implemented yet" << std::endl;
                return Value();
                
            case BuiltinCallExpression::BuiltinType::SOCKET:
                // Placeholder implementation
                std::cout << "Socket operations not implemented yet" << std::endl;
                return Value();
                
            default:
                throw InterpreterError("Unknown builtin function");
        }
    }
    
    // Throw an error for unknown expression types
    throw InterpreterError("Unknown expression type");
}

Value Interpreter::evaluateLiteral(std::shared_ptr<Expression> expr) {
    auto literal = std::dynamic_pointer_cast<LiteralExpression>(expr);
    if (!literal) return Value();
    
    const auto& literalValue = literal->getValue();
    
    if (std::holds_alternative<int64_t>(literalValue)) {
        return Value(std::get<int64_t>(literalValue));
    } else if (std::holds_alternative<double>(literalValue)) {
        return Value(std::get<double>(literalValue));
    } else if (std::holds_alternative<bool>(literalValue)) {
        return Value(std::get<bool>(literalValue));
    } else if (std::holds_alternative<char>(literalValue)) {
        return Value(std::get<char>(literalValue));
    } else if (std::holds_alternative<std::string>(literalValue)) {
        return Value(std::get<std::string>(literalValue));
    } else if (std::holds_alternative<std::nullptr_t>(literalValue)) {
        return Value(); // Void/null
    }
    
    throw InterpreterError("Unsupported literal type");
}

Value Interpreter::evaluateIdentifier(std::shared_ptr<Expression> expr) {
    auto identifier = std::dynamic_pointer_cast<IdentifierExpression>(expr);
    if (!identifier) return Value();
    
    std::string varName = identifier->getName();
    
    try {
        // Try current environment first
        return environment->get(varName);
    } catch (const InterpreterError& e) {
        try {
            // If not in current environment, try globals
            return globals->get(varName);
        } catch (const InterpreterError& globalErr) {
            // Detailed logging of environments
            std::cerr << "Variable '" << varName << "' not found." << std::endl;
            std::cerr << "Current Environment Symbols:" << std::endl;
            environment->printSymbols();
            std::cerr << "\nGlobal Environment Symbols:" << std::endl;
            globals->printSymbols();
            
            // Rethrow the original error
            throw;
        }
    }
}

Value Interpreter::evaluateArray(std::shared_ptr<Expression> expr) {
    auto arrayLiteral = std::dynamic_pointer_cast<ArrayLiteralExpression>(expr);
    if (!arrayLiteral) return Value();
    
    std::vector<Value> elements;
    for (const auto& element : arrayLiteral->getElements()) {
        elements.push_back(evaluate(element));
    }
    
    return Value(elements);
}

Value Interpreter::evaluateUnary(std::shared_ptr<Expression> expr) {
    auto unary = std::dynamic_pointer_cast<UnaryExpression>(expr);
    if (!unary) return Value();
    
    Value operand = evaluate(unary->getOperand());
    
    switch (unary->getOperator()) {
        case UnaryExpression::Operator::NEG:
            if (operand.isInteger()) {
                return Value(-operand.as<int64_t>());
            } else if (operand.isFloat()) {
                return Value(-operand.as<double>());
            }
            throw InterpreterError("Operand must be a number");
            
        case UnaryExpression::Operator::NOT:
            return Value(!isTruthy(operand));
            
        case UnaryExpression::Operator::BIT_NOT:
            if (operand.isInteger()) {
                return Value(~operand.as<int64_t>());
            }
            throw InterpreterError("Operand must be an integer");
            
        default:
            throw InterpreterError("Unknown unary operator");
    }
}

Value Interpreter::evaluateBinary(std::shared_ptr<Expression> expr) {
    auto binary = std::dynamic_pointer_cast<BinaryExpression>(expr);
    if (!binary) return Value();

    // Handle assignment separately
    if (binary->getOperator() == BinaryExpression::Operator::ASSIGN) {
        // For assignment, the left side should be an identifier
        auto identifier = std::dynamic_pointer_cast<IdentifierExpression>(binary->getLeft());
        if (!identifier) {
            throw InterpreterError("Invalid assignment target");
        }
        
        // Evaluate the right side
        Value value = evaluate(binary->getRight());
        
        // Assign the value to the variable
        environment->assign(identifier->getName(), value);
        
        return value;
    }

    Value left = evaluate(binary->getLeft());
    Value right = evaluate(binary->getRight());
    
    switch (binary->getOperator()) {
        case BinaryExpression::Operator::ADD:
            // String concatenation
            if (left.isString() && right.isString()) {
                return Value(left.as<std::string>() + right.as<std::string>());
            }
            // Numeric addition
            if (left.isNumber() && right.isNumber()) {
                if (left.isFloat() || right.isFloat()) {
                    double leftVal = left.isFloat() ? left.as<double>() : 
                                     static_cast<double>(left.as<int64_t>());
                    double rightVal = right.isFloat() ? right.as<double>() : 
                                      static_cast<double>(right.as<int64_t>());
                    return Value(leftVal + rightVal);
                }
                // Both are integers
                return Value(left.as<int64_t>() + right.as<int64_t>());
            }
            throw InterpreterError("Invalid operands for addition");
            
        case BinaryExpression::Operator::EQ:
            return Value(isEqual(left, right));
            
        // Add more cases for other binary operators as needed
        
        default:
            throw InterpreterError("Unsupported binary operator");
    }
}

Value Interpreter::evaluateCall(std::shared_ptr<Expression> expr) {
    auto call = std::dynamic_pointer_cast<CallExpression>(expr);
    if (!call) return Value();

    // Special handling for method calls (object.method())
    if (auto memberAccess = std::dynamic_pointer_cast<MemberAccessExpression>(call->getCallee())) {
        // Evaluate the object
        Value objectValue = evaluate(memberAccess->getObject());
        
        // Get the method name
        const std::string& methodName = memberAccess->getMember();
        
        // If it's an object, look for the method
        if (objectValue.isObject()) {
            const auto& objectMap = objectValue.as<std::unordered_map<std::string, Value>>();
            auto it = objectMap.find(methodName);
            
            if (it != objectMap.end() && it->second.isCallable()) {
                // Evaluate arguments
                std::vector<Value> arguments;
                for (const auto& arg : call->getArgs()) {
                    arguments.push_back(evaluate(arg));
                }
                
                // Get the method
                auto method = it->second.as<std::shared_ptr<Callable>>();
                
                // Call the method with the arguments
                return method->call(*this, arguments);
            }
            
            throw InterpreterError("Object has no method '" + methodName + "'");
        }
        
        throw InterpreterError("Cannot call method on non-object value");
    }
    
    // Normal function call handling
    Value callee = evaluate(call->getCallee());
    
    // Check if it's a callable object
    if (!callee.isCallable()) {
        throw InterpreterError("Can only call functions and methods");
    }
    
    // Evaluate arguments
    std::vector<Value> arguments;
    for (const auto& arg : call->getArgs()) {
        arguments.push_back(evaluate(arg));
    }
    
    // Get the callable function
    auto function = callee.as<std::shared_ptr<Callable>>();
    
    // Check arity (if applicable)
    if (function->arity() >= 0 && static_cast<int>(arguments.size()) != function->arity()) {
        // Special case for print, which is variadic
        if (function->arity() == -1 && arguments.empty()) {
            throw InterpreterError("print requires at least one argument");
        }
    }
    
    // Call the function and return its result
    return function->call(*this, arguments);
}

Value Interpreter::evaluateMemberAccess(std::shared_ptr<Expression> expr) {
    auto memberAccess = std::dynamic_pointer_cast<MemberAccessExpression>(expr);
    if (!memberAccess) return Value();

    // Evaluate the object expression
    Value object = evaluate(memberAccess->getObject());
    
    // Get the member name
    const std::string& memberName = memberAccess->getMember();
    
    //std::cout << "Accessing member: " << memberName << std::endl;
    
    // Check if the object is an actual object (map of key/values)
    if (object.isObject()) {
        // Access the member from the object
        const auto& objectMap = object.as<std::unordered_map<std::string, Value>>();
        
        // Print object contents for debugging
        /*std::cout << "  Object contains keys:" << std::endl;
        for (const auto& [key, value] : objectMap) {
            std::cout << "    - " << key << ": " << value.toString() << std::endl;
        }*/
        
        auto it = objectMap.find(memberName);
        
        if (it != objectMap.end()) {
            //std::cout << "  Found member: " << memberName << " = " << it->second.toString() << std::endl;
            return it->second;
        }
        
        throw InterpreterError("Object does not have member '" + memberName + "'");
    }
    
    // For arrow operator (pointer dereferencing)
    if (memberAccess->getIsArrow()) {
        // For pointers, we would dereference first
        throw InterpreterError("Pointer dereferencing not implemented");
    }
    
    throw InterpreterError("Cannot access member '" + memberName + "' on non-object value");
}

Value Interpreter::evaluateIndex(std::shared_ptr<Expression> expr) {
    auto index = std::dynamic_pointer_cast<IndexExpression>(expr);
    if (!index) return Value();

    // Evaluate the array and index expressions
    Value arrayValue = evaluate(index->getArray());
    
    // Check if it's a string
    if (arrayValue.isString()) {
        const std::string& str = arrayValue.as<std::string>();
        
        // Check if the index is a range (has a colon)
        if (auto binaryIndex = std::dynamic_pointer_cast<BinaryExpression>(index->getIndex())) {
            // Check if it's a colon operation
            if (binaryIndex->getOperator() == BinaryExpression::Operator::CUSTOM && 
                binaryIndex->getCustomOperator() == ":") {
                
                // Evaluate start and end indices
                Value startValue = evaluate(binaryIndex->getLeft());
                Value endValue = evaluate(binaryIndex->getRight());
                
                // Ensure indices are integers
                if (!endValue.isInteger()) {
                    throw InterpreterError("String slice end index must be an integer");
                }
                
                int64_t start, end;
                end = endValue.as<int64_t>();
                
                // Check if start is a special null/void literal
                auto startLiteral = std::dynamic_pointer_cast<LiteralExpression>(binaryIndex->getLeft());
                if (startLiteral && startLiteral->getValue().index() == 0) {
                    // When start is missing, calculate from the end
                    start = std::max<int64_t>(0, static_cast<int64_t>(str.length()) - end);
                } else {
                    // Get the start value from the literal
                    start = startValue.as<int64_t>();
                }
                
                // Adjust indices to be within string bounds
                start = std::max<int64_t>(0, std::min<int64_t>(start, static_cast<int64_t>(str.length())));
                end = std::max<int64_t>(0, std::min<int64_t>(end, static_cast<int64_t>(str.length())));
                
                // Extract substring
                return Value(str.substr(start, end - start));
            }
        }
        
        // Fallback to single index access
        if (std::dynamic_pointer_cast<IdentifierExpression>(index->getIndex()) == nullptr) {
            Value indexValue = evaluate(index->getIndex());
            
            if (!indexValue.isInteger()) {
                throw InterpreterError("String index must be an integer");
            }
            
            int64_t i = indexValue.as<int64_t>();
            
            if (i < 0 || i >= static_cast<int64_t>(str.length())) {
                throw InterpreterError("String index out of bounds");
            }
            
            // Return the character at the specified index
            return Value(std::string(1, str[i]));
        }
    }
    
    // For arrays
    if (arrayValue.isArray()) {
        if (std::dynamic_pointer_cast<IdentifierExpression>(index->getIndex()) == nullptr) {
            Value indexValue = evaluate(index->getIndex());
            
            if (!indexValue.isInteger()) {
                throw InterpreterError("Array index must be an integer");
            }
            
            int64_t i = indexValue.as<int64_t>();
            const auto& array = arrayValue.as<std::vector<Value>>();
            
            if (i < 0 || i >= static_cast<int64_t>(array.size())) {
                throw InterpreterError("Array index out of bounds");
            }
            
            // Return the element at the specified index
            return array[i];
        }
    }
    
    // Check if it's an object (for property access by string key)
    if (arrayValue.isObject()) {
        if (auto identExpr = std::dynamic_pointer_cast<IdentifierExpression>(index->getIndex())) {
            const std::string& key = identExpr->getName();
            const auto& object = arrayValue.as<std::unordered_map<std::string, Value>>();
            
            auto it = object.find(key);
            if (it != object.end()) {
                return it->second;
            }
            
            throw InterpreterError("Object does not have property '" + key + "'");
        }
    }
    
    throw InterpreterError("Cannot use index operator on non-indexable value");
}

// Improved evaluateScopeResolution method

Value Interpreter::evaluateScopeResolution(std::shared_ptr<Expression> expr) {
    auto scopeResolution = std::dynamic_pointer_cast<ScopeResolutionExpression>(expr);
    if (!scopeResolution) return Value();

    // Get scope and identifier
    std::shared_ptr<Expression> scopeExpr = scopeResolution->getScope();
    const std::string& identifier = scopeResolution->getIdentifier();
    
    std::cout << "Evaluating scope resolution: " << identifier << std::endl;
    
    // Handle nested scope resolution (A::B::C)
    if (auto nestedScopeExpr = std::dynamic_pointer_cast<ScopeResolutionExpression>(scopeExpr)) {
        std::cout << "  Detected nested scope resolution" << std::endl;
        
        // First evaluate the left part of the scope resolution
        Value leftScope = evaluate(scopeExpr);
        
        if (leftScope.isObject()) {
            std::cout << "  Successfully evaluated left scope" << std::endl;
            
            // Search for the right identifier in the left scope
            const auto& leftScopeMap = leftScope.as<std::unordered_map<std::string, Value>>();
            auto it = leftScopeMap.find(identifier);
            
            if (it != leftScopeMap.end()) {
                std::cout << "  Found identifier in nested scope: " << identifier << std::endl;
                return it->second;
            } else {
                std::cout << "  Identifier not found in nested scope: " << identifier << std::endl;
                // Print available keys for debugging
                std::cout << "  Available keys in nested scope:" << std::endl;
                for (const auto& [key, _] : leftScopeMap) {
                    std::cout << "    - " << key << std::endl;
                }
            }
        } else {
            std::cout << "  Left scope is not an object, trying alternative approaches" << std::endl;
        }
        
        // Try the fully qualified path
        try {
            // Get the full qualified path by reconstructing it
            std::string leftPath;
            std::string rightId = nestedScopeExpr->getIdentifier();
            
            if (auto leftIdent = std::dynamic_pointer_cast<IdentifierExpression>(nestedScopeExpr->getScope())) {
                leftPath = leftIdent->getName();
            } else {
                // More complex nested resolution
                std::cout << "  Complex nested resolution - trying combinations" << std::endl;
            }
            
            // Try different case variations for the namespace
            std::vector<std::string> caseVariations;
            caseVariations.push_back(leftPath); // Original case
            
            // Add lowercase variation
            std::string lowerPath = leftPath;
            std::transform(lowerPath.begin(), lowerPath.end(), lowerPath.begin(), ::tolower);
            if (lowerPath != leftPath) caseVariations.push_back(lowerPath);
            
            for (const auto& casePath : caseVariations) {
                // Try lookup with fully qualified name
                std::string fullPath = casePath + "::" + rightId + "::" + identifier;
                std::cout << "  Trying full path: " << fullPath << std::endl;
                
                try {
                    return globals->get(fullPath);
                } catch (const InterpreterError& e) {
                    std::cout << "  Full path not found: " << fullPath << std::endl;
                }
                
                // Try with just the right part
                std::string partialPath = rightId + "::" + identifier;
                std::cout << "  Trying partial path: " << partialPath << std::endl;
                
                try {
                    return globals->get(partialPath);
                } catch (const InterpreterError& e) {
                    std::cout << "  Partial path not found: " << partialPath << std::endl;
                }
            }
        } catch (const std::exception& e) {
            std::cout << "  Error during path lookup: " << e.what() << std::endl;
        }
    }
    
    // Simple namespace::identifier case
    if (auto identExpr = std::dynamic_pointer_cast<IdentifierExpression>(scopeExpr)) {
        const std::string& scope = identExpr->getName();
        std::cout << "  Scope name: " << scope << std::endl;
        
        // Look up the scope in the global environment
        try {
            Value scopeValue = globals->get(scope);
            std::cout << "  Found scope: " << scope << std::endl;
            
            if (scopeValue.isObject()) {
                // Look for identifier in the object/namespace
                const auto& scopeMap = scopeValue.as<std::unordered_map<std::string, Value>>();
                auto it = scopeMap.find(identifier);
                
                if (it != scopeMap.end()) {
                    std::cout << "  Found member in scope: " << identifier << std::endl;
                    return it->second;
                } else {
                    std::cout << "  Member not found in scope: " << identifier << std::endl;
                    // Print available members for debugging
                    std::cout << "  Available members:" << std::endl;
                    for (const auto& [key, value] : scopeMap) {
                        std::cout << "    - " << key << std::endl;
                    }
                }
            }
            
            // Try direct qualified name lookup as fallback
            std::string qualifiedName = scope + "::" + identifier;
            std::cout << "  Trying qualified name: " << qualifiedName << std::endl;
            try {
                return globals->get(qualifiedName);
            } catch (const InterpreterError& e) {
                std::cout << "  Qualified name not found: " << qualifiedName << std::endl;
            }
        } catch (const InterpreterError& e) {
            std::cout << "  Scope not found: " << scope << std::endl;
            
            // Try case-insensitive match
            std::cout << "  Trying case-insensitive match for: " << scope << std::endl;
            std::unordered_map<std::string, Value> globalMap = globals->getAllSymbols();
            
            for (const auto& [key, value] : globalMap) {
                // Convert both to lowercase for comparison
                std::string keyLower = key;
                std::string scopeLower = scope;
                std::transform(keyLower.begin(), keyLower.end(), keyLower.begin(), ::tolower);
                std::transform(scopeLower.begin(), scopeLower.end(), scopeLower.begin(), ::tolower);
                
                if (keyLower == scopeLower) {
                    std::cout << "  Found case-insensitive match: " << key << std::endl;
                    
                    // Now try to access members
                    if (value.isObject()) {
                        const auto& scopeMap = value.as<std::unordered_map<std::string, Value>>();
                        auto it = scopeMap.find(identifier);
                        
                        if (it != scopeMap.end()) {
                            std::cout << "  Found member in scope: " << identifier << std::endl;
                            return it->second;
                        } else {
                            std::cout << "  Member not found in case-insensitive scope: " << identifier << std::endl;
                            // Print available members for debugging
                            std::cout << "  Available members:" << std::endl;
                            for (const auto& [memberKey, memberValue] : scopeMap) {
                                std::cout << "    - " << memberKey << std::endl;
                            }
                        }
                        
                        // Try qualified name with the correct case
                        std::string qualifiedName = key + "::" + identifier;
                        std::cout << "  Trying qualified name with correct case: " << qualifiedName << std::endl;
                        try {
                            return globals->get(qualifiedName);
                        } catch (const InterpreterError& e) {
                            std::cout << "  Qualified name not found: " << qualifiedName << std::endl;
                        }
                    }
                    
                    break;
                }
            }
        }
    }
    globals->printSymbols();
    
    throw InterpreterError("Cannot resolve '" + identifier + "' in scope");
}

// Add this method to the Environment class to support case-insensitive lookups
std::unordered_map<std::string, Value> Environment::getAllSymbols() const {
    return values;
}

void Interpreter::executeNamespaceDeclaration(std::shared_ptr<NamespaceDeclaration> decl) {
    std::string namespaceName = decl->getName();
    std::cout << "Processing namespace: " << namespaceName << std::endl;
    
    // Create namespace environment
    std::unordered_map<std::string, Value> namespaceEnv;
    
    // Process namespace members (classes)
    for (const auto& classDecl : decl->getClasses()) {
        std::string className = classDecl->getName();
        std::string qualifiedName = namespaceName + "::" + className;
        std::cout << "  Processing class: " << className << " (qualified: " << qualifiedName << ")" << std::endl;
        
        // Create class environment
        std::unordered_map<std::string, Value> classEnv;
        
        // Process class members
        for (const auto& member : classDecl->getMembers()) {
            if (auto objDecl = std::dynamic_pointer_cast<ObjectDeclaration>(member)) {
                // Process object declaration
                std::string objName = objDecl->getName();
                std::string objQualifiedName = qualifiedName + "::" + objName;
                std::cout << "    Processing object: " << objName << " (qualified: " << objQualifiedName << ")" << std::endl;
                
                // Create object environment
                std::unordered_map<std::string, Value> objEnv;
                
                // Process object members
                for (const auto& objMember : objDecl->getMembers()) {
                    if (auto varDecl = std::dynamic_pointer_cast<VariableDeclaration>(objMember)) {
                        std::string varName = varDecl->getName();
                        std::cout << "      Processing field: " << varName << std::endl;
                        
                        // Evaluate initializer if present
                        Value varValue;
                        if (varDecl->getInitializer()) {
                            try {
                                // For string literals, extract directly
                                if (auto literalExpr = std::dynamic_pointer_cast<LiteralExpression>(varDecl->getInitializer())) {
                                    const auto& literalValue = literalExpr->getValue();
                                    
                                    if (std::holds_alternative<std::string>(literalValue)) {
                                        std::string strValue = std::get<std::string>(literalValue);
                                        varValue = Value(strValue);
                                        std::cout << "        Set string value: " << strValue << std::endl;
                                    }
                                    else if (std::holds_alternative<int64_t>(literalValue)) {
                                        int64_t intValue = std::get<int64_t>(literalValue);
                                        varValue = Value(intValue);
                                        std::cout << "        Set integer value: " << intValue << std::endl;
                                    }
                                    else if (std::holds_alternative<double>(literalValue)) {
                                        double doubleValue = std::get<double>(literalValue);
                                        varValue = Value(doubleValue);
                                        std::cout << "        Set float value: " << doubleValue << std::endl;
                                    }
                                    else if (std::holds_alternative<bool>(literalValue)) {
                                        bool boolValue = std::get<bool>(literalValue);
                                        varValue = Value(boolValue);
                                        std::cout << "        Set boolean value: " << (boolValue ? "true" : "false") << std::endl;
                                    }
                                    else if (std::holds_alternative<char>(literalValue)) {
                                        char charValue = std::get<char>(literalValue);
                                        // Store char as string for simplicity
                                        varValue = Value(std::string(1, charValue));
                                        std::cout << "        Set char value: " << charValue << std::endl;
                                    }
                                }
                                else {
                                    // Try normal evaluation
                                    varValue = evaluate(varDecl->getInitializer());
                                    std::cout << "        Evaluated to: " << varValue.toString() << std::endl;
                                }
                            } catch (const std::exception& e) {
                                std::cerr << "        Error evaluating initializer: " << e.what() << std::endl;
                            }
                        }
                        
                        // Add field to object environment
                        objEnv[varName] = varValue;
                        std::cout << "      Added field to object: " << varName << " = " << varValue.toString() << std::endl;
                    }
                }
                
                // Add object to class environment
                classEnv[objName] = Value(objEnv);
                
                // Register the object in the global environment with its qualified name
                globals->define(objQualifiedName, Value(objEnv));
                std::cout << "    Registered qualified object: " << objQualifiedName << std::endl;
                std::cout << "    Object contents: ";
                for (const auto& [key, value] : objEnv) {
                    std::cout << key << "=" << value.toString() << " ";
                }
            }
        }
        
        // Register class in global environment with qualified name
        globals->define(qualifiedName, Value(classEnv));
        std::cout << "  Registered qualified class: " << qualifiedName << std::endl;
        
        // Add to namespace environment
        namespaceEnv[className] = Value(classEnv);
    }
    
    // Register namespace in global environment
    globals->define(namespaceName, Value(namespaceEnv));
    std::cout << "Registered namespace: " << namespaceName << std::endl;
}

void Interpreter::executeClassDeclaration(std::shared_ptr<ClassDeclaration> decl) {
    std::string className = decl->getName();
    
    // Create class environment
    std::unordered_map<std::string, Value> classEnv;
    
    // Process class members
    for (const auto& member : decl->getMembers()) {
        if (auto objDecl = std::dynamic_pointer_cast<ObjectDeclaration>(member)) {
            // Process object members
            std::string objName = objDecl->getName();
            std::string qualifiedName = className + "_" + objName;
            
            // Create object value
            std::unordered_map<std::string, Value> objEnv;
            
            // Process object members
            for (const auto& objMember : objDecl->getMembers()) {
                if (auto varDecl = std::dynamic_pointer_cast<VariableDeclaration>(objMember)) {
                    std::string varName = varDecl->getName();
                    std::string fullyQualifiedName = qualifiedName + "_" + varName;
                    
                    // Evaluate initializer if present
                    Value varValue;
                    if (varDecl->getInitializer()) {
                        varValue = evaluate(varDecl->getInitializer());
                    }
                    
                    // Register in global environment
                    globals->define(fullyQualifiedName, varValue);
                    
                    // Add to object environment
                    objEnv[varName] = varValue;
                }
                else if (auto funcDecl = std::dynamic_pointer_cast<FunctionDeclaration>(objMember)) {
                    std::string funcName = funcDecl->getName();
                    std::string fullyQualifiedName = qualifiedName + "_" + funcName;
                    
                    // Create function object
                    auto function = std::make_shared<Function>(funcDecl, environment);
                    
                    // Register in global environment with qualified name
                    globals->define(fullyQualifiedName, Value(function));
                    
                    // Add to object environment
                    objEnv[funcName] = Value(function);
                }
            }
            
            // Register object in global environment
            globals->define(qualifiedName, Value(objEnv));
            
            // Add to class environment
            classEnv[objName] = Value(objEnv);
        }
        else if (auto structDecl = std::dynamic_pointer_cast<StructDeclaration>(member)) {
            // Process struct declaration
            executeStructDeclaration(structDecl);
        }
    }
    
    // Register class in global environment
    globals->define(className, Value(classEnv));
}

void Interpreter::executeStructDeclaration(std::shared_ptr<StructDeclaration> decl) {
    std::string structName = decl->getName();
    
    std::unordered_map<std::string, Value> structTemplate;
    
    for (const auto& field : decl->getFields()) {
        Value fieldValue;
        if (field.getInitializer()) {
            try {
                fieldValue = evaluate(field.getInitializer());
            } catch (const std::exception& e) {
                std::cerr << "Error evaluating initializer for field " 
                          << field.getName() << ": " << e.what() << std::endl;
            }
        }
        
        structTemplate[field.getName()] = fieldValue;
    }
    
    // For anonymous structs, don't register in globals
    if (!structName.empty()) {
        globals->define(structName, Value(structTemplate));
    } else {
        // If it's an anonymous struct, still make it accessible
        environment->define("__anonymous_struct", Value(structTemplate));
    }
}

void Interpreter::executeObjectDeclaration(std::shared_ptr<ObjectDeclaration> decl) {
    std::string objName = decl->getName();

    
    // Create object environment
    std::unordered_map<std::string, Value> objEnv;
    
    // Process object members
    for (const auto& member : decl->getMembers()) {
        if (auto varDecl = std::dynamic_pointer_cast<VariableDeclaration>(member)) {
            std::string varName = varDecl->getName();

            
            // Evaluate initializer if present
            Value varValue;
            if (varDecl->getInitializer()) {
                try {
                    // Handle string literals and other constants
                    if (auto literalExpr = std::dynamic_pointer_cast<LiteralExpression>(varDecl->getInitializer())) {
                        const auto& literalValue = literalExpr->getValue();
                        
                        if (std::holds_alternative<std::string>(literalValue)) {
                            std::string strValue = std::get<std::string>(literalValue);
                            varValue = Value(strValue);

                        }
                        else if (std::holds_alternative<int64_t>(literalValue)) {
                            varValue = Value(std::get<int64_t>(literalValue));
                        }
                        else if (std::holds_alternative<double>(literalValue)) {
                            varValue = Value(std::get<double>(literalValue));
                        }
                        else if (std::holds_alternative<bool>(literalValue)) {
                            varValue = Value(std::get<bool>(literalValue));
                        }
                        else if (std::holds_alternative<char>(literalValue)) {
                            // Store char as string for simplicity
                            varValue = Value(std::string(1, std::get<char>(literalValue)));
                        }
                    }
                    else {
                        // Try normal evaluation
                        varValue = evaluate(varDecl->getInitializer());
                    }
                } catch (const std::exception& e) {
                    std::cerr << "    Error evaluating initializer: " << e.what() << std::endl;
                }
            }
            
            // Add to object environment
            objEnv[varName] = varValue;

        }
    }
    
    // Register object in environment
    environment->define(objName, Value(objEnv));

}

Value Interpreter::evaluateInjectableString(std::shared_ptr<Expression> expr) {
    auto injectableExpr = std::dynamic_pointer_cast<InjectableStringExpression>(expr);
    if (!injectableExpr) {
        throw InterpreterError("Invalid injectable string expression");
    }

    // Get the format string and arguments
    const std::string& format = injectableExpr->getFormat();
    const auto& args = injectableExpr->getArgs();

    // Create a result string
    std::string result;
    
    // Track current position in the format string and argument position
    size_t pos = 0;
    size_t argIndex = 0;

    // Evaluate all arguments first
    std::vector<Value> evaluatedArgs;
    for (const auto& arg : args) {
        evaluatedArgs.push_back(evaluate(arg));
    }

    // Iterate through the format string
    while (pos < format.length()) {
        // Find the next placeholder
        size_t placeholderPos = format.find("{}", pos);
        
        if (placeholderPos == std::string::npos) {
            // No more placeholders, append remaining string
            result += format.substr(pos);
            break;
        }
        
        // Append text before the placeholder
        result += format.substr(pos, placeholderPos - pos);
        
        // Replace placeholder with evaluated argument
        if (argIndex < evaluatedArgs.size()) {
            result += evaluatedArgs[argIndex].toString();
            argIndex++;
        } else {
            // If no more arguments, leave placeholder as-is
            result += "{}";
        }
        
        // Move position to after the placeholder
        pos = placeholderPos + 2;
    }
    
    // Return as a string value
    return Value(result);
}

Value Interpreter::evaluateObjectInstantiation(std::shared_ptr<Expression> expr) {
    auto objInst = std::dynamic_pointer_cast<ObjectInstantiationExpression>(expr);
    if (!objInst) return Value();
    
    std::string objectName = objInst->getObjectName();

    
    // Handle qualified types (A::B::C)
    if (objInst->hasQualifiedType()) {

        
        // Extract the qualified name directly from the type expression
        std::string qualifiedName;
        
        if (auto scopeExpr = std::dynamic_pointer_cast<ScopeResolutionExpression>(objInst->getTypeExpr())) {
            qualifiedName = extractQualifiedName(scopeExpr);

        } else if (auto identExpr = std::dynamic_pointer_cast<IdentifierExpression>(objInst->getTypeExpr())) {
            qualifiedName = identExpr->getName();

        }
        
        if (qualifiedName.empty()) {
            throw InterpreterError("Failed to extract qualified name from type expression");
        }
        
        // Try case-insensitive match for the qualified name

        
        // Try direct lookup first
        Value templateValue;
        bool found = false;
        
        try {
            templateValue = globals->get(qualifiedName);
            found = true;
        } catch (const InterpreterError&) {
            // Try case-insensitive lookup
            
            // Try with lowercase first part (myns instead of MyNS)
            size_t pos = qualifiedName.find("::");
            if (pos != std::string::npos) {
                std::string firstPart = qualifiedName.substr(0, pos);
                std::string restPart = qualifiedName.substr(pos);
                
                std::string lowerFirstPart = firstPart;
                std::transform(lowerFirstPart.begin(), lowerFirstPart.end(), 
                              lowerFirstPart.begin(), ::tolower);
                
                std::string alternateName = lowerFirstPart + restPart;
                
                try {
                    templateValue = globals->get(alternateName);
                    found = true;
                } catch (const InterpreterError&) {
                    // Continue with full case-insensitive search
                }
            }
            
            // Full case-insensitive search
            if (!found) {
                std::unordered_map<std::string, Value> globalMap = globals->getAllSymbols();
                std::string lowerQualifiedName = qualifiedName;
                std::transform(lowerQualifiedName.begin(), lowerQualifiedName.end(), 
                              lowerQualifiedName.begin(), ::tolower);
                
                for (const auto& [key, value] : globalMap) {
                    std::string lowerKey = key;
                    std::transform(lowerKey.begin(), lowerKey.end(), lowerKey.begin(), ::tolower);
                    
                    if (lowerKey == lowerQualifiedName || 
                        key.find("::") != std::string::npos && 
                        lowerKey.substr(lowerKey.find("::")) == lowerQualifiedName.substr(lowerQualifiedName.find("::"))) {
                        templateValue = value;
                        found = true;
                        break;
                    }
                }
            }
        }
        
        if (!found) {
            throw InterpreterError("Cannot find object template for: " + qualifiedName);
        }
        
        // Clone the template
        if (templateValue.isObject()) {
            auto objectTemplate = templateValue.as<std::unordered_map<std::string, Value>>();
            
            // Create a new instance
            auto objectInstance = objectTemplate;
            
            // Register in the current environment
            environment->define(objectName, Value(objectInstance));
            

            
            return Value(objectInstance);
        }
        
        throw InterpreterError("Template is not an object: " + qualifiedName);
    }
    
    // Handle simple unqualified types
    std::string objectType = objInst->getObjectType();
    
    // Look up the object type in the environment
    Value objectTypeValue;
    try {
        objectTypeValue = environment->get(objectType);
    } catch (const InterpreterError&) {
        try {
            objectTypeValue = globals->get(objectType);
        } catch (const InterpreterError&) {
            throw InterpreterError("Unknown object type '" + objectType + "'");
        }
    }
    
    // Clone the object (if it's an object)
    if (objectTypeValue.isObject()) {
        auto objectTemplate = objectTypeValue.as<std::unordered_map<std::string, Value>>();
        
        // Create a new instance of the object by copying the template
        auto objectInstance = objectTemplate;
        
        // Define the new object in the environment
        environment->define(objectName, Value(objectInstance));
        
        // Return the object instance
        return Value(objectInstance);
    }
    
    throw InterpreterError("Cannot create instance of non-object type '" + objectType + "'");
}

// Helper method to build qualified name from scope resolution expression
std::string Interpreter::buildQualifiedName(std::shared_ptr<ScopeResolutionExpression> scopeExpr) {
    if (!scopeExpr) return "";
    
    // Get the right identifier part
    std::string result = scopeExpr->getIdentifier();
    
    // Process the left part of the scope expression
    std::shared_ptr<Expression> leftExpr = scopeExpr->getScope();
    
    // If the left part is another scope resolution, recurse
    if (auto nestedScope = std::dynamic_pointer_cast<ScopeResolutionExpression>(leftExpr)) {
        std::string leftPart = buildQualifiedName(nestedScope);
        if (!leftPart.empty()) {
            result = leftPart + "::" + result;
        }
    }
    // If the left part is an identifier, get its name
    else if (auto identExpr = std::dynamic_pointer_cast<IdentifierExpression>(leftExpr)) {
        std::string leftPart = identExpr->getName();
        if (!leftPart.empty()) {
            result = leftPart + "::" + result;
        }
    }
    
    return result;
}

std::string Interpreter::extractQualifiedName(std::shared_ptr<ScopeResolutionExpression> expr) {
    if (!expr) return "";
    
    std::string result = expr->getIdentifier();
    
    // Process the left part
    auto left = expr->getScope();
    
    if (auto nestedScope = std::dynamic_pointer_cast<ScopeResolutionExpression>(left)) {
        // Handle nested scope resolution recursively
        std::string prefix = extractQualifiedName(nestedScope);
        if (!prefix.empty()) {
            result = prefix + "::" + result;
        }
    } else if (auto identExpr = std::dynamic_pointer_cast<IdentifierExpression>(left)) {
        // Handle simple identifier
        std::string prefix = identExpr->getName();
        if (!prefix.empty()) {
            result = prefix + "::" + result;
        }
    }
    
    return result;
}

} // namespace flux
