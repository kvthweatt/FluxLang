#include "parser.h"
#include <sstream>
#include <iostream>
#include <cassert>

namespace flux {
namespace parser {

// Constructor with tokenizer
Parser::Parser(lexer::Tokenizer& tokenizer)
    : tokenizer_(tokenizer), panicMode_(false), inFunctionBody_(false), 
      inObjectBody_(false), inControlStructure_(false), inTemplateDeclaration_(false) {
    
    // Initialize synchronization points for error recovery
    syncPoints_[lexer::TokenType::SEMICOLON] = true;
    syncPoints_[lexer::TokenType::RIGHT_BRACE] = true;
    syncPoints_[lexer::TokenType::KEYWORD_CLASS] = true;
    syncPoints_[lexer::TokenType::KEYWORD_OBJECT] = true;
    syncPoints_[lexer::TokenType::KEYWORD_DEF] = true;
    syncPoints_[lexer::TokenType::KEYWORD_NAMESPACE] = true;
    syncPoints_[lexer::TokenType::KEYWORD_SECTION] = true;
    
    // Prime the parser with the first token
    advance();
}

// Debugging helper to dump the next token
void Parser::dumpNextToken() {
    std::cout << "Current token: " << current_.toString() << std::endl;
}

// Reset parsing state
void Parser::resetParsingState() {
    panicMode_ = false;
}

// Advance with guard to prevent errors at end of token stream
void Parser::advanceWithGuard(const char* context) {
    if (check(lexer::TokenType::END_OF_FILE)) {
        std::cerr << "Attempt to advance past end of token stream in " << context << std::endl;
        return;
    }
    advance();
}

// Advance to the next token
lexer::Token Parser::advance() {
    previous_ = current_;
    
    // Debug for line 77
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77 ADVANCE: Before tokenizer call - current: " << current_.toString() << std::endl;
    }
    
    // Check if we're already at the end of the file
    if (current_.type() == lexer::TokenType::END_OF_FILE) {
        return previous_;
    }
    
    current_ = tokenizer_.nextToken();
    
    // Debug for line 77
    if (previous_.start().line == 77) {
        std::cout << "DEBUG LINE 77 ADVANCE: After tokenizer call - new current: " << current_.toString() << std::endl;
    }
    
    // Skip error tokens
    while (current_.type() == lexer::TokenType::ERROR) {
        std::cout << "DEBUG ADVANCE: Skipping error token: " << current_.toString() << std::endl;
        error(current_, current_.lexeme());
        current_ = tokenizer_.nextToken();
        
        if (previous_.start().line == 77) {
            std::cout << "DEBUG LINE 77 ADVANCE: After skipping error, new current: " << current_.toString() << std::endl;
        }
    }
    
    // Debug for line 77
    if (previous_.start().line == 77) {
        std::cout << "DEBUG LINE 77 ADVANCE: Final result - previous: " << previous_.toString() << ", current: " << current_.toString() << std::endl;
    }
    
    return previous_;
}

// Check if the current token is of the given type
bool Parser::check(lexer::TokenType type) const {
    return current_.type() == type;
}

// Check if the current token is of any of the given types
bool Parser::checkAny(std::initializer_list<lexer::TokenType> types) const {
    for (auto type : types) {
        if (current_.type() == type) {
            return true;
        }
    }
    return false;
}

// Check if the next token is of the given type without consuming it
bool Parser::checkNext(lexer::TokenType type) {
    if (check(lexer::TokenType::END_OF_FILE)) return false;
    
    // Save current token
    auto current = current_;
    advance(); // Move to next token
    bool match = previous_.type() == type;
    current_ = current; // Restore position
    
    return match;
}

// Match and consume the current token if it's of the given type
bool Parser::match(lexer::TokenType type) {
    if (!check(type)) return false;
    
    // Debug for line 77
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77 MATCH: About to advance from token: " << current_.toString() << std::endl;
    }
    
    advance();
    
    // Debug for line 77
    if (previous_.start().line == 77) {
        std::cout << "DEBUG LINE 77 MATCH: After advance - previous: " << previous_.toString() << ", current: " << current_.toString() << std::endl;
    }
    
    return true;
}

// Match and consume the current token if it's one of the given types
bool Parser::match(std::initializer_list<lexer::TokenType> types) {
    for (auto type : types) {
        if (check(type)) {
            advance();
            return true;
        }
    }
    return false;
}

// Consume the current token if it's of the expected type, otherwise report an error
lexer::Token Parser::consume(lexer::TokenType type, std::string_view message) {
    if (check(type)) {
        return advance();
    }
    
    // Regular error handling without auto-insertion
    if (!panicMode_) {
        error(current_, message);
        panicMode_ = true;  // Enter panic mode to suppress cascading errors
    }
    
    return errorToken(message);
}

// Synchronize after an error to recover parsing
void Parser::synchronize() {
    panicMode_ = false;
    
    // Skip until we reach a statement boundary or declaration start
    while (!check(lexer::TokenType::END_OF_FILE)) {
        if (previous_.is(lexer::TokenType::SEMICOLON)) {
            return; // Found a statement boundary
        }
        
        // Look for declaration starts
        switch (current_.type()) {
            case lexer::TokenType::KEYWORD_NAMESPACE:
            case lexer::TokenType::KEYWORD_CLASS:
            case lexer::TokenType::KEYWORD_OBJECT:
            case lexer::TokenType::KEYWORD_DEF:
            case lexer::TokenType::KEYWORD_IF:
            case lexer::TokenType::KEYWORD_FOR:
            case lexer::TokenType::KEYWORD_DO:
            case lexer::TokenType::KEYWORD_WHILE:
            case lexer::TokenType::KEYWORD_RETURN:
            case lexer::TokenType::KEYWORD_SECTION:
            case lexer::TokenType::RIGHT_BRACE: // Stop at closing brace
            case lexer::TokenType::KEYWORD_OPERATOR:
                return;
            default:
                // Do nothing
                break;
        }
        
        advance();
    }
}

// Report an error at the current position
void Parser::error(std::string_view message) {
    error(current_, message);
}

// Report an error at the given token
void Parser::error(const lexer::Token& token, std::string_view message) {
    if (panicMode_) return;
    
    std::stringstream ss;
    ss << message;
    
    common::SourcePosition start = token.start();
    common::SourcePosition end = token.end();
    
    output::SourceLocation location(
        tokenizer_.errors().errors().empty() ? 
            "" : tokenizer_.errors().errors()[0].location().filename,
        start.line,
        start.column
    );
    
    errors_.addError(common::ErrorCode::PARSER_ERROR, ss.str(), location);
    
    // Set panic mode to prevent error cascades
    panicMode_ = true;
}

// Create an error token
lexer::Token Parser::errorToken(std::string_view message) {
    return lexer::Token(
        lexer::TokenType::ERROR,
        message,
        current_.start(),
        current_.end()
    );
}

// Create a source range from start and end tokens
common::SourceRange Parser::makeRange(const lexer::Token& start, const lexer::Token& end) const {
    return {start.start(), end.end()};
}

// Create a source range from a single token
common::SourceRange Parser::makeRange(const lexer::Token& token) const {
    return {token.start(), token.end()};
}

// Create a source range from start and end positions
common::SourceRange Parser::makeRange(
    const common::SourcePosition& start, 
    const common::SourcePosition& end) const {
    return {start, end};
}

// Parse a complete program
std::unique_ptr<Program> Parser::parseProgram() {
    auto program = std::make_unique<Program>();
    
    // Process tokens until we reach the end of file
    while (!check(lexer::TokenType::END_OF_FILE)) {
        // Try parsing as a declaration
        auto decl = declaration();
        
        if (decl) {
            program->addDeclaration(std::move(decl));
        } else {
            // Not a valid declaration - report error and advance
            error("Expected declaration");
            
            // Always advance the token to prevent infinite loop
            advance();
            
            // Synchronize to a known good state
            synchronize();
        }
        
        // Check if we've reached the end of the file after parsing
        if (check(lexer::TokenType::END_OF_FILE)) {
            break;
        }
    }
    
    return program;
}

// Parse a declaration
std::unique_ptr<Decl> Parser::declaration() {
    try {
        // Check for section attribute first as it can wrap other declarations
        if (match(lexer::TokenType::KEYWORD_SECTION)) {
            return sectionDeclaration();
        }
        
        // Check for volatile modifier
        bool isVolatile = false;
        if (match(lexer::TokenType::KEYWORD_VOLATILE)) {
            isVolatile = true;
        }
        
        // Handle keyword-based declarations
        if (match(lexer::TokenType::KEYWORD_NAMESPACE)) return namespaceDeclaration();
        if (match(lexer::TokenType::KEYWORD_OBJECT)) {
            // Check if this is an object template
            if (checkNext(lexer::TokenType::KEYWORD_TEMPLATE)) {
                return objectTemplateDeclaration();
            }
            return objectDeclaration();
        }
        if (match(lexer::TokenType::KEYWORD_CLASS)) return classDeclaration();
        if (match(lexer::TokenType::KEYWORD_STRUCT)) return structDeclaration();
        if (match(lexer::TokenType::KEYWORD_DEF)) return functionDeclaration();
        if (match(lexer::TokenType::KEYWORD_CONST)) return variableDeclaration(true, isVolatile);
        if (match(lexer::TokenType::KEYWORD_IMPORT)) return importDeclaration();
        if (match(lexer::TokenType::KEYWORD_USING)) return usingDeclaration();
        if (match(lexer::TokenType::KEYWORD_OPERATOR)) return operatorDeclaration();
        if (match(lexer::TokenType::KEYWORD_TEMPLATE)) return templateDeclaration();
        if (match(lexer::TokenType::KEYWORD_ENUM)) return enumDeclaration();
        if (match(lexer::TokenType::KEYWORD_TYPE)) return typeDeclaration();
        if (match({lexer::TokenType::KEYWORD_DATA, 
                  lexer::TokenType::KEYWORD_SIGNED, 
                  lexer::TokenType::KEYWORD_UNSIGNED})) {
            return dataDeclaration();
        }
        if (match(lexer::TokenType::KEYWORD_ASM)) return asmDeclaration();
        
        // If there was a volatile modifier, apply it to variable declaration
        if (isVolatile) {
            return variableDeclaration(false, true);
        }
        
        // Try to parse as an identifier-based declaration
        if (check(lexer::TokenType::IDENTIFIER)) {
            return identifierDeclaration();
        }
        
        // Not a declaration
        return nullptr;
        
    } catch (const std::exception& e) {
        std::cerr << "Error in declaration parsing: " << e.what() << std::endl;
        synchronize();
        return nullptr;
    }
}

// Parse a declaration starting with an identifier
std::unique_ptr<Decl> Parser::identifierDeclaration() {
    // Only proceed if we're looking at an identifier
    if (!check(lexer::TokenType::IDENTIFIER)) {
        return nullptr;
    }
    
    // Save the current token for potential backtracking
    auto savePos = current_;
    auto firstIdent = current_;
    advance(); // Consume identifier
    
    // Case 1: Function pointer declaration (Type *name(ParamType1, ParamType2) = func;)
    if (match(lexer::TokenType::ASTERISK)) {
        // Check if this is a regular pointer variable (not a function pointer)
        if (check(lexer::TokenType::IDENTIFIER)) {
            auto pointerName = current_;
            advance(); // Consume pointer variable name
            
            // Check for initializer
            std::unique_ptr<Expr> initializer = nullptr;
            if (match(lexer::TokenType::EQUAL)) {
                // Check for address-of operator (common in pointer initialization)
                if (match(lexer::TokenType::AT_REF)) {
                    if (check(lexer::TokenType::IDENTIFIER)) {
                        auto addressOfVar = current_;
                        advance(); // Consume variable name
                        
                        // Create variable expression
                        auto varExpr = std::make_unique<VariableExpr>(addressOfVar);
                        
                        // Create address-of unary expression
                        initializer = std::make_unique<UnaryExpr>(
                            previous_, // @ operator
                            std::move(varExpr),
                            true, // prefix
                            makeRange(previous_, addressOfVar)
                        );
                    } else {
                        error("Expected identifier after '@'");
                    }
                } else {
                    // Regular initializer expression
                    initializer = expression();
                    if (!initializer) {
                        error("Expected expression after '='");
                    }
                }
            }
            
            consume(lexer::TokenType::SEMICOLON, "Expected ';' after variable declaration");
            
            // Create base type
            auto baseType = std::make_unique<NamedTypeExpr>(
                firstIdent.lexeme(),
                makeRange(firstIdent)
            );
            
            // Create pointer type
            auto pointerType = std::make_unique<PointerTypeExpr>(
                std::move(baseType),
                makeRange(firstIdent, previous_),
                false, // Not volatile
                false  // Not const
            );
            
            // Create variable declaration for the pointer
            return std::make_unique<VarDecl>(
                pointerName.lexeme(),
                std::move(pointerType),
                std::move(initializer),
                false, // not const
                false, // not volatile
                makeRange(firstIdent, previous_)
            );
        }
    }
    
    // Case 2: Object instantiation (someObj{} obj; or someObj(args){} obj;)
    bool hasConstructorArgs = false;
    
    // Check for constructor arguments
    if (match(lexer::TokenType::LEFT_PAREN)) {
        hasConstructorArgs = true;
        
        // Skip through constructor arguments
        if (!check(lexer::TokenType::RIGHT_PAREN)) {
            do {
                auto arg = expression();
                if (!arg) {
                    error("Expected constructor argument");
                    break;
                }
            } while (match(lexer::TokenType::COMMA));
        }
        
        consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after constructor arguments");
    }
    
    // Check for empty braces initialization
    if (match(lexer::TokenType::LEFT_BRACE)) {
        consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after class instantiation");
        
        // Check for instance name
        if (check(lexer::TokenType::IDENTIFIER)) {
            auto instanceName = current_;
            advance(); // Consume instance name
            
            consume(lexer::TokenType::SEMICOLON, "Expected ';' after class instantiation");
            
            // Create class type and variable declaration
            auto classType = std::make_unique<NamedTypeExpr>(
                firstIdent.lexeme(),
                makeRange(firstIdent)
            );
            
            return std::make_unique<VarDecl>(
                instanceName.lexeme(),
                std::move(classType),
                nullptr, // No initializer needed for {} instantiation
                false,   // Not const
                false,   // Not volatile
                makeRange(firstIdent, previous_)
            );
        } else {
            error("Expected instance name after class instantiation");
            synchronize();
            current_ = savePos; // Rewind to try other declaration types
            return nullptr;
        }
    }
    
    // Case 3: Normal variable declaration (Type name = initializer;)
    if (hasConstructorArgs) {
        // We had constructor args but no braces, not a valid declaration
        current_ = savePos;
        return nullptr;
    }
    
    // Check for pointer type
    bool isPointerType = false;
    if (match(lexer::TokenType::ASTERISK)) {
        isPointerType = true;
    }
    
    // Check for array type
    bool isArrayType = false;
    std::unique_ptr<Expr> arraySizeExpr;
    
    if (match(lexer::TokenType::LEFT_BRACKET)) {
        isArrayType = true;
        
        // Parse array size expression if present
        if (!check(lexer::TokenType::RIGHT_BRACKET)) {
            arraySizeExpr = expression();
        }
        
        consume(lexer::TokenType::RIGHT_BRACKET, "Expected ']' after array type");
    }

    // Variable name
    if (check(lexer::TokenType::IDENTIFIER)) {
        auto varName = current_;
        advance(); // Consume variable name
        
        // Optional initializer
        std::unique_ptr<Expr> initializer;
        if (match(lexer::TokenType::EQUAL)) {
            initializer = expression();
            if (!initializer) {
                error("Expected initializer expression");
            }
        }
        
        consume(lexer::TokenType::SEMICOLON, "Expected ';' after variable declaration");
        
        // Create appropriate type
        std::unique_ptr<TypeExpr> type;
        
        // Base type
        auto baseType = std::make_unique<NamedTypeExpr>(
            firstIdent.lexeme(),
            makeRange(firstIdent)
        );
        
        // Apply modifiers (pointer or array)
        if (isPointerType) {
            type = std::make_unique<PointerTypeExpr>(
                std::move(baseType),
                makeRange(firstIdent, previous_),
                false, // Not volatile
                false  // Not const
            );
        } else if (isArrayType) {
            type = std::make_unique<ArrayTypeExpr>(
                std::move(baseType),
                std::move(arraySizeExpr),
                makeRange(firstIdent, previous_)
            );
        } else {
            type = std::move(baseType);
        }
        
        // Create and return the variable declaration
        return std::make_unique<VarDecl>(
            varName.lexeme(),
            std::move(type),
            std::move(initializer),
            false, // Not const
            false, // Not volatile
            makeRange(firstIdent, previous_)
        );
    }
    
    // Not a valid declaration, rewind and return nullptr
    current_ = savePos;
    return nullptr;
}

// Parse a namespace declaration
std::unique_ptr<Decl> Parser::namespaceDeclaration() {
    // Parse the namespace name
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected namespace name");
    
    // Parse the namespace body
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after namespace name");
    
    std::vector<std::unique_ptr<Decl>> declarations;
    
    while (!check(lexer::TokenType::RIGHT_BRACE) && 
           !check(lexer::TokenType::END_OF_FILE)) {
        auto decl = declaration();
        if (decl) {
            declarations.push_back(std::move(decl));
        } else {
            // If declaration parsing fails, report error and skip token
            error("Expected declaration in namespace");
            
            // Skip to next token and check if we're at end of namespace
            if (!check(lexer::TokenType::RIGHT_BRACE) && 
                !check(lexer::TokenType::END_OF_FILE)) {
                advance();
            } else {
                break; // Break if we're at the end
            }
        }
    }
    
    auto endToken = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after namespace body");
    
    // Consume optional semicolon after namespace 
    if (check(lexer::TokenType::SEMICOLON)) {
        advance();
    }
    
    return std::make_unique<NamespaceDecl>(
        name.lexeme(),
        std::move(declarations),
        makeRange(name, endToken)
    );
}

// Parse a class declaration
std::unique_ptr<Decl> Parser::classDeclaration() {
    auto classKeyword = previous_;  // 'class' keyword
    
    // Parse alignment attribute if present
    std::optional<size_t> alignment = parseAlignmentAttribute();
    
    // Check for packed modifier
    bool isPacked = match(lexer::TokenType::KEYWORD_PACKED);
    
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected class name");
    
    // Parse inheritance list only - no separate exclusion list parsing
    std::vector<std::string_view> baseClasses = parseInheritanceList();
    
    // Handle forward declaration
    if (match(lexer::TokenType::SEMICOLON)) {
        return std::make_unique<ClassDecl>(
            name.lexeme(),
            std::move(baseClasses),
            std::vector<std::string_view>{}, // Empty exclusions for now
            std::vector<std::unique_ptr<Decl>>{},
            makeRange(classKeyword, previous_),
            true,   // This is a forward declaration
            isPacked,
            alignment
        );
    }
    
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after class name");
    
    // Set flags for context
    bool oldInFunctionBody = inFunctionBody_;
    inFunctionBody_ = false;
    
    std::vector<std::unique_ptr<Decl>> members;
    
    while (!check(lexer::TokenType::RIGHT_BRACE) && !check(lexer::TokenType::END_OF_FILE)) {
        // Handle member variable declarations
        if (check(lexer::TokenType::IDENTIFIER)) {
            auto typeToken = current_;
            advance();  // Consume type name
            
            if (check(lexer::TokenType::IDENTIFIER)) {
                auto nameToken = current_;
                advance();  // Consume variable name
                
                // Handle initializer
                std::unique_ptr<Expr> initializer = nullptr;
                if (match(lexer::TokenType::EQUAL)) {
                    if (check(lexer::TokenType::CHAR_LITERAL)) {
                        auto stringToken = current_;
                        advance();  // Consume string literal
                        initializer = std::make_unique<LiteralExpr>(
                            stringToken,
                            std::string(stringToken.stringValue())
                        );
                    } else {
                        initializer = expression();
                        if (!initializer) {
                            error("Expected initializer expression");
                        }
                    }
                }
                
                consume(lexer::TokenType::SEMICOLON, "Expected ';' after variable declaration");
                
                // Create type expression
                auto typeExpr = std::make_unique<NamedTypeExpr>(
                    typeToken.lexeme(),
                    makeRange(typeToken)
                );
                
                // Create variable declaration
                members.push_back(std::make_unique<VarDecl>(
                    nameToken.lexeme(),
                    std::move(typeExpr),
                    std::move(initializer),
                    false,  // Not const
                    false,  // Not volatile
                    makeRange(typeToken, previous_)
                ));
                
                continue;
            }
            
            // If it wasn't a variable declaration, reset position
            current_ = typeToken;
        }
        
        // Check for def keyword - explicitly disallow and report error
        if (check(lexer::TokenType::KEYWORD_DEF)) {
            error("Functions cannot be defined directly inside classes in Flux");
            advance();  // Consume 'def'
            
            // Skip over the whole function definition to avoid cascading errors
            synchronize();
            continue;
        }
        
        // Handle object declarations inside class
        if (check(lexer::TokenType::KEYWORD_OBJECT) || 
            check(lexer::TokenType::KEYWORD_STRUCT)) {
            
            // Don't call declaration() here - call the specific object/struct parsing
            std::unique_ptr<Decl> member;
            
            if (match(lexer::TokenType::KEYWORD_OBJECT)) {
                member = objectDeclaration();
            } else if (match(lexer::TokenType::KEYWORD_STRUCT)) {
                member = structDeclaration();
            }
            
            if (member) {
                members.push_back(std::move(member));
                continue;
            }
        }
        
        // Try parsing other kinds of declarations
        auto member = declaration();
        if (member) {
            members.push_back(std::move(member));
        } else {
            error("Expected member declaration in class");
            
            // Skip to the next token to avoid infinite loops
            if (!check(lexer::TokenType::RIGHT_BRACE) && 
                !check(lexer::TokenType::END_OF_FILE)) {
                advance();
            }
            
            // Try to synchronize to a stable state
            synchronize();
        }
    }
    
    // Restore previous function body flag
    inFunctionBody_ = oldInFunctionBody;
    
    auto endBrace = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after class body");
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after class declaration");
    
    return std::make_unique<ClassDecl>(
        name.lexeme(),
        std::move(baseClasses),
        std::vector<std::string_view>{}, // Empty exclusions for now
        std::move(members),
        makeRange(classKeyword, previous_),
        false,  // Not a forward declaration
        isPacked,
        alignment
    );
}

// Helper to parse inheritance list (e.g., <ParentClass1, ParentClass2>)
std::vector<std::string_view> Parser::parseInheritanceList() {
    std::vector<std::string_view> baseClasses;
    
    // Only consume inheritance list if we actually see a '<'
    if (match(lexer::TokenType::LESS)) {
        do {
            // Skip over exclusion marker if present (handle inline exclusions)
            if (match(lexer::TokenType::EXCLAMATION)) {
                // Skip exclusion for now, don't add to base classes
                if (check(lexer::TokenType::IDENTIFIER)) {
                    advance(); // consume the excluded identifier
                }
                continue;
            }
            
            if (check(lexer::TokenType::IDENTIFIER)) {
                auto baseName = current_;
                advance(); // consume identifier
                baseClasses.push_back(baseName.lexeme());
            } else {
                error("Expected class/object name in inheritance list");
                break;
            }
        } while (match(lexer::TokenType::COMMA));
        
        consume(lexer::TokenType::GREATER, "Expected '>' after inheritance list");
    }
    
    return baseClasses;
}

// Helper to parse exclusion list (e.g., <ParentClass1, !ExcludedMember>)
std::vector<std::string_view> Parser::parseExclusionList() {
    std::vector<std::string_view> exclusions;
    
    // If we already parsed the inheritance list, look for exclusions in braces
    if (match(lexer::TokenType::LEFT_BRACE)) {
        if (match(lexer::TokenType::EXCLAMATION)) {
            auto excludedMember = consume(lexer::TokenType::IDENTIFIER, "Expected member name to exclude");
            exclusions.push_back(excludedMember.lexeme());
            
            consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after exclusion list");
        } else {
            // Not an exclusion list, rewind
            error("Expected '!' for exclusion list");
            // Rewind to before the left brace
            advance();
        }
    }
    
    return exclusions;
}

// Parse an object declaration
std::unique_ptr<Decl> Parser::objectDeclaration() {
    auto objectKeyword = previous_;  // 'object' keyword
    
    // Debug output
    //std::cout << "DEBUG: Parsing object at line " << current_.start().line << ", current token: " << current_.toString() << std::endl;
    
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected object name");
    
    //std::cout << "DEBUG: Object name: " << name.lexeme() << ", next token: " << current_.toString() << std::endl;
    
    // Parse inheritance list
    std::vector<std::string_view> baseObjects = parseInheritanceList();
    
    //std::cout << "DEBUG: After inheritance, current token: " << current_.toString() << std::endl;
    
    // Handle forward declaration
    if (match(lexer::TokenType::SEMICOLON)) {
        //std::cout << "DEBUG: Forward declaration" << std::endl;
        return std::make_unique<ObjectDecl>(
            name.lexeme(),
            std::move(baseObjects),
            std::vector<std::unique_ptr<Decl>>{},
            makeRange(objectKeyword, previous_),
            true,  // This is a forward declaration
            false, // Not a template
            std::vector<std::string_view>{}
        );
    }
    
    // The error is likely happening here - the parser expects { but finds something else
    //std::cout << "DEBUG: Looking for '{', current token: " << current_.toString() << std::endl;
    
    // Expect opening brace for object body
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after object name");
    
    // Set flag to indicate we're in an object body
    bool oldObjectFlag = inObjectBody_;
    inObjectBody_ = true;
    
    // Parse object members
    std::vector<std::unique_ptr<Decl>> members = parseObjectMembers();
    
    // Restore previous object body flag
    inObjectBody_ = oldObjectFlag;
    
    auto endBrace = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after object body");
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after object declaration");
    
    return std::make_unique<ObjectDecl>(
        name.lexeme(),
        std::move(baseObjects),
        std::move(members),
        makeRange(objectKeyword, previous_),
        false,  // Not a forward declaration
        false,  // Not a template
        std::vector<std::string_view>{}
    );
}

// Parse an object template declaration
std::unique_ptr<Decl> Parser::objectTemplateDeclaration() {
    auto objectKeyword = previous_;  // 'object' keyword
    
    consume(lexer::TokenType::KEYWORD_TEMPLATE, "Expected 'template' keyword");
    
    // Parse template parameters
    consume(lexer::TokenType::LESS, "Expected '<' after 'template'");
    std::vector<std::string_view> templateParams;
    
    if (!check(lexer::TokenType::GREATER)) {
        do {
            auto paramName = consume(lexer::TokenType::IDENTIFIER, "Expected template parameter name");
            templateParams.push_back(paramName.lexeme());
        } while (match(lexer::TokenType::COMMA));
    }
    
    consume(lexer::TokenType::GREATER, "Expected '>' after template parameters");
    
    // Parse object name
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected object name");
    
    // Parse inheritance list
    std::vector<std::string_view> baseObjects = parseInheritanceList();
    
    // Handle forward declaration
    if (match(lexer::TokenType::SEMICOLON)) {
        return std::make_unique<ObjectDecl>(
            name.lexeme(),
            std::move(baseObjects),
            std::vector<std::unique_ptr<Decl>>{},
            makeRange(objectKeyword, previous_),
            true,  // This is a forward declaration
            true,  // Is a template
            std::move(templateParams)
        );
    }
    
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after object name");
    
    // Set flags to indicate we're in an object template body
    bool oldObjectFlag = inObjectBody_;
    bool oldTemplateFlag = inTemplateDeclaration_;
    inObjectBody_ = true;
    inTemplateDeclaration_ = true;
    
    // Parse object members
    std::vector<std::unique_ptr<Decl>> members = parseObjectMembers();
    
    // Restore previous flags
    inObjectBody_ = oldObjectFlag;
    inTemplateDeclaration_ = oldTemplateFlag;
    
    auto endBrace = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after object body");
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after object declaration");
    
    return std::make_unique<ObjectDecl>(
        name.lexeme(),
        std::move(baseObjects),
        std::move(members),
        makeRange(objectKeyword, previous_),
        false,  // Not a forward declaration
        true,   // Is a template
        std::move(templateParams)
    );
}

// Helper to parse object members (used by both objects and object templates)
std::vector<std::unique_ptr<Decl>> Parser::parseObjectMembers() {
    std::vector<std::unique_ptr<Decl>> members;
    
    while (!check(lexer::TokenType::RIGHT_BRACE) && !check(lexer::TokenType::END_OF_FILE)) {
        // Handle method declarations first
        if (match(lexer::TokenType::KEYWORD_DEF)) {
            auto member = functionDeclaration();
            if (member) {
                members.push_back(std::move(member));
                continue;
            }
        }
        
        // Handle member variable declarations
        if (check(lexer::TokenType::IDENTIFIER)) {
            auto typeToken = current_;
            advance();  // Consume type name
            
            if (check(lexer::TokenType::IDENTIFIER)) {
                auto nameToken = current_;
                advance();  // Consume variable name
                
                // Handle initializer
                std::unique_ptr<Expr> initializer = nullptr;
                if (match(lexer::TokenType::EQUAL)) {
                    // Handle string literals specially
                    if (check(lexer::TokenType::CHAR_LITERAL)) {
                        auto stringToken = current_;
                        advance();  // Consume string literal
                        initializer = std::make_unique<LiteralExpr>(
                            stringToken,
                            std::string(stringToken.stringValue())
                        );
                    } else {
                        // Parse other expressions
                        initializer = expression();
                        if (!initializer) {
                            error("Expected initializer expression");
                        }
                    }
                }
                
                // Consume semicolon
                consume(lexer::TokenType::SEMICOLON, "Expected ';' after variable declaration");
                
                // Create type expression
                auto typeExpr = std::make_unique<NamedTypeExpr>(
                    typeToken.lexeme(),
                    makeRange(typeToken)
                );
                
                // Create variable declaration
                members.push_back(std::make_unique<VarDecl>(
                    nameToken.lexeme(),
                    std::move(typeExpr),
                    std::move(initializer),
                    false,  // Not const
                    false,  // Not volatile
                    makeRange(typeToken, previous_)
                ));
                
                continue;
            }
            
            // If it wasn't a variable declaration, reset position
            current_ = typeToken;
        }
        
        // Try parsing other kinds of declarations
        auto member = declaration();
        if (member) {
            members.push_back(std::move(member));
        } else {
            error("Expected member declaration in object");
            
            // Skip to the next token to avoid infinite loops
            if (!check(lexer::TokenType::RIGHT_BRACE) && 
                !check(lexer::TokenType::END_OF_FILE)) {
                advance();
            }
            
            // Try to synchronize to a stable state
            synchronize();
        }
    }
    
    return members;
}

// Parse a struct declaration
std::unique_ptr<Decl> Parser::structDeclaration() {
    auto structKeyword = previous_;  // 'struct' keyword
    
    // Parse alignment attribute if present
    std::optional<size_t> alignment = parseAlignmentAttribute();
    
    // Check for packed modifier
    bool isPacked = match(lexer::TokenType::KEYWORD_PACKED);
    
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected struct name");
    
    // Handle forward declaration
    if (match(lexer::TokenType::SEMICOLON)) {
        return std::make_unique<StructDecl>(
            name.lexeme(),
            std::vector<StructDecl::Field>{},
            makeRange(structKeyword, previous_),
            isPacked,
            alignment
        );
    }
    
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after struct name");
    
    // Parse fields
    std::vector<StructDecl::Field> fields;
    
    while (!check(lexer::TokenType::RIGHT_BRACE) && 
           !check(lexer::TokenType::END_OF_FILE)) {
        
        // Check for field type
        if (checkAny({lexer::TokenType::IDENTIFIER, 
                      lexer::TokenType::KEYWORD_VOLATILE,
                      lexer::TokenType::KEYWORD_CONST})) {
            
            // Check for volatile modifier
            bool isVolatile = match(lexer::TokenType::KEYWORD_VOLATILE);
            
            // Check for const modifier (ignore for fields, just consume it)
            if (match(lexer::TokenType::KEYWORD_CONST)) {
                // Just consume it, we don't use it for struct fields
            }
            
            // Parse field type
            auto fieldType = type();
            if (!fieldType) {
                error("Expected field type in struct");
                synchronize();
                continue;
            }
            
            // Parse field name
            auto fieldName = consume(lexer::TokenType::IDENTIFIER, "Expected field name after type");
            
            // Parse alignment attribute for field if present
            std::optional<size_t> fieldAlignment = parseAlignmentAttribute();
            
            // Consume the semicolon
            consume(lexer::TokenType::SEMICOLON, "Expected ';' after field declaration");
            
            // Add the field to the list
            fields.emplace_back(
                fieldName.lexeme(),
                std::move(fieldType),
                fieldAlignment,
                isVolatile
            );
        } else {
            error("Expected field declaration in struct");
            
            // Skip to the next token to avoid infinite loops
            if (!check(lexer::TokenType::RIGHT_BRACE) && 
                !check(lexer::TokenType::END_OF_FILE)) {
                advance();
            }
        }
    }
    
    auto endBrace = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after struct body");
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after struct declaration");
    
    return std::make_unique<StructDecl>(
        name.lexeme(),
        std::move(fields),
        makeRange(structKeyword, previous_),
        isPacked,
        alignment
    );
}

// Parse a function declaration
std::unique_ptr<Decl> Parser::functionDeclaration() {
    // Save previous function body state
    bool oldInFunctionBody = inFunctionBody_;
    
    // Parse the function name
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected function name");

    // Parse the parameter list
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after function name");
    std::vector<FunctionDecl::Parameter> parameters;
    
    if (!check(lexer::TokenType::RIGHT_PAREN)) {
        do {
            // Handle qualified types in parameters (e.g., Flux.Integer)
            if (check(lexer::TokenType::IDENTIFIER)) {
                // Start parsing a qualified type
                auto firstPart = current_;
                advance(); // Consume first part of the type
                
                // Build the qualified type
                std::string qualifiedType = std::string(firstPart.lexeme());
                
                // Check for dot notation (qualified identifier)
                while (match(lexer::TokenType::DOT)) {
                    if (check(lexer::TokenType::IDENTIFIER)) {
                        qualifiedType += ".";
                        qualifiedType += current_.lexeme();
                        advance(); // Consume the next part of the qualified name
                    } else {
                        error("Expected identifier after '.' in qualified type");
                        break;
                    }
                }
                
                // Check for pointer type
                bool isPointer = match(lexer::TokenType::ASTERISK);
                
                // Create the appropriate type expression
                std::unique_ptr<TypeExpr> paramType;
                auto baseType = std::make_unique<NamedTypeExpr>(
                    qualifiedType,
                    makeRange(firstPart, previous_)
                );
                
                if (isPointer) {
                    paramType = std::make_unique<PointerTypeExpr>(
                        std::move(baseType),
                        makeRange(firstPart, previous_),
                        false, // Not volatile
                        false  // Not const
                    );
                } else {
                    paramType = std::move(baseType);
                }
                
                // Parse parameter name
                std::string_view paramName;
                if (check(lexer::TokenType::IDENTIFIER)) {
                    auto nameToken = current_;
                    advance(); // Consume the parameter name
                    paramName = nameToken.lexeme();
                } else {
                    // Use a generic parameter name if not specified
                    paramName = "param" + std::to_string(parameters.size());
                    // Provide a helpful error message
                    error("Expected parameter name after type");
                }
                
                // Add the parameter to the list
                parameters.emplace_back(paramName, std::move(paramType));
            } else {
                error("Expected parameter type or name");
                if (!check(lexer::TokenType::COMMA) && !check(lexer::TokenType::RIGHT_PAREN)) {
                    advance(); // Skip problematic token
                }
            }
        } while (match(lexer::TokenType::COMMA));
    }
    
    auto rightParen = consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after parameters");

    // Parse the return type
    std::unique_ptr<TypeExpr> returnType;
    
    if (match(lexer::TokenType::ARROW)) {
        // Handle qualified return types (e.g., Flux.Integer)
        if (check(lexer::TokenType::IDENTIFIER)) {
            auto firstPart = current_;
            advance(); // Consume first part
            
            // Build the qualified return type
            std::string qualifiedType = std::string(firstPart.lexeme());
            
            // Check for dot notation
            while (match(lexer::TokenType::DOT)) {
                if (check(lexer::TokenType::IDENTIFIER)) {
                    qualifiedType += ".";
                    qualifiedType += current_.lexeme();
                    advance();
                } else {
                    error("Expected identifier after '.' in return type");
                    break;
                }
            }
            
            // Check for pointer return type
            bool isPointer = match(lexer::TokenType::ASTERISK);
            
            // Create return type
            auto baseType = std::make_unique<NamedTypeExpr>(
                qualifiedType,
                makeRange(firstPart, previous_)
            );
            
            if (isPointer) {
                returnType = std::make_unique<PointerTypeExpr>(
                    std::move(baseType),
                    makeRange(firstPart, previous_),
                    false, // Not volatile
                    false  // Not const
                );
            } else {
                returnType = std::move(baseType);
            }
        }
        // Handle special return types like void and !void
        else if (match(lexer::TokenType::KEYWORD_VOID)) {
            returnType = std::make_unique<NamedTypeExpr>("void", makeRange(previous_));
        } else if (match(lexer::TokenType::BANG_VOID)) {
            returnType = std::make_unique<NamedTypeExpr>("!void", makeRange(previous_));
        } else if (match(lexer::TokenType::EXCLAMATION)) {
            if (match(lexer::TokenType::KEYWORD_VOID)) {
                returnType = std::make_unique<NamedTypeExpr>("!void", makeRange(previous_, previous_));
            } else {
                error("Expected 'void' after '!' in return type");
            }
        } else {
            error("Expected return type after '->'");
        }
    }

    // Mark that we're in a function body
    inFunctionBody_ = true;
    
    // Parse the function body or prototype
    std::unique_ptr<Stmt> body;
    bool isPrototype = false;
    
    // Check if this is a function prototype (ends with semicolon)
    if (match(lexer::TokenType::SEMICOLON)) {
        isPrototype = true;
        // Create an empty body for prototype
        body = std::make_unique<BlockStmt>(
            std::vector<std::unique_ptr<Stmt>>{},
            makeRange(previous_)
        );
    } 
    // Otherwise, parse a regular function body with braces
    else if (match(lexer::TokenType::LEFT_BRACE)) {
        // Use the blockStatement method to handle function body statements
        body = blockStatement();
        
        // Always consume the semicolon after function body
        consume(lexer::TokenType::SEMICOLON, "Expected ';' after function body");
    } else {
        error("Expected '{' to begin function body or ';' for function prototype");
        // Create an empty body to avoid null pointers
        body = std::make_unique<BlockStmt>(
            std::vector<std::unique_ptr<Stmt>>{},
            makeRange(previous_)
        );
    }
    
    // Restore previous function body state
    inFunctionBody_ = oldInFunctionBody;
    
    // Create and return the function declaration
    return std::make_unique<FunctionDecl>(
        name.lexeme(),
        std::move(parameters),
        std::move(returnType),
        std::move(body),
        makeRange(name, previous_),
        isPrototype
    );
}

// Parse a variable declaration
std::unique_ptr<Decl> Parser::variableDeclaration(bool isConst, bool isVolatile) {
    // Parse the variable type
    std::unique_ptr<TypeExpr> varType;
    auto typeToken = current_;
    
    // Type is required for variable declarations
    varType = type();
    if (!varType) {
        error("Expected type for variable declaration");
        return nullptr;
    }
    
    // Parse the variable name
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected variable name");
    
    // Parse initializer (optional)
    std::unique_ptr<Expr> initializer;
    if (match(lexer::TokenType::EQUAL)) {
        // Check for string literals specifically
        if (match(lexer::TokenType::CHAR_LITERAL)) {
            auto stringToken = previous_;
            // Create a literal expression directly instead of using expression()
            initializer = std::make_unique<LiteralExpr>(
                stringToken,
                std::string(stringToken.stringValue())
            );
        } else {
            // For other expressions, use the regular expression parser
            initializer = expression();
        }
    }
    
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after variable declaration");
    
    return std::make_unique<VarDecl>(
        name.lexeme(),
        std::move(varType),
        std::move(initializer),
        isConst,
        isVolatile,
        makeRange(typeToken, previous_)
    );
}

// Parse an import declaration
std::unique_ptr<Decl> Parser::importDeclaration() {
    // Parse the import path
    auto path = consume(lexer::TokenType::CHAR_LITERAL, "Expected import path");
    
    // Parse alias (optional)
    std::optional<std::string_view> alias;
    if (match(lexer::TokenType::KEYWORD_AS)) {
        alias = consume(lexer::TokenType::IDENTIFIER, "Expected import alias").lexeme();
    }
    
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after import declaration");
    
    return std::make_unique<ImportDecl>(
        path.stringValue(),
        alias,
        makeRange(path, previous_)
    );
}

// Parse a using declaration
std::unique_ptr<Decl> Parser::usingDeclaration() {
    // Parse the using path
    std::vector<std::string_view> path;
    
    auto first = consume(lexer::TokenType::IDENTIFIER, "Expected identifier in using path");
    path.push_back(first.lexeme());
    
    while (match(lexer::TokenType::DOT)) {
        auto part = consume(lexer::TokenType::IDENTIFIER, "Expected identifier after '.'");
        path.push_back(part.lexeme());
    }
    
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after using declaration");
    
    return std::make_unique<UsingDecl>(
        std::move(path),
        makeRange(first, previous_)
    );
}

// Parse an operator declaration
std::unique_ptr<Decl> Parser::operatorDeclaration() {
    auto start = previous_;  // 'operator' keyword
    
    // Parse parameter list
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'operator'");
    
    // Parse parameters
    std::vector<OperatorDecl::Parameter> parameters;
    
    if (!check(lexer::TokenType::RIGHT_PAREN)) {
        do {
            // Parse parameter type
            auto paramType = type();
            if (!paramType) {
                error("Expected parameter type in operator declaration");
                continue;
            }
            
            // Parse parameter name
            std::string_view paramName;
            if (check(lexer::TokenType::IDENTIFIER)) {
                auto nameToken = current_;
                advance(); // Consume parameter name
                paramName = nameToken.lexeme();
            } else {
                error("Expected parameter name after type");
                paramName = "param" + std::to_string(parameters.size());
            }
            
            // Add parameter to list
            parameters.emplace_back(paramName, std::move(paramType));
        } while (match(lexer::TokenType::COMMA));
    }
    
    consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after parameters");
    
    // Parse operator name/symbol in square brackets
    consume(lexer::TokenType::LEFT_BRACKET, "Expected '[' after parameters");
    
    std::string_view opSymbol;
    if (check(lexer::TokenType::IDENTIFIER)) {
        opSymbol = current_.lexeme();
        advance(); // Consume operator name
    } else {
        error("Expected operator name inside brackets");
        opSymbol = "unknown";
    }
    
    consume(lexer::TokenType::RIGHT_BRACKET, "Expected ']' after operator name");
    
    // Parse return type
    std::unique_ptr<TypeExpr> returnType;
    
    if (match(lexer::TokenType::ARROW)) {
        // Check for !void
        if (match(lexer::TokenType::EXCLAMATION)) {
            if (match(lexer::TokenType::KEYWORD_VOID)) {
                returnType = std::make_unique<NamedTypeExpr>("!void", makeRange(previous_, previous_));
            } else {
                error("Expected 'void' after '!' in return type");
                returnType = std::make_unique<NamedTypeExpr>("void", makeRange(previous_));
            }
        } else if (match(lexer::TokenType::BANG_VOID)) {
            // Handle combined !void token
            returnType = std::make_unique<NamedTypeExpr>("!void", makeRange(previous_));
        } else {
            // Parse normal return type
            returnType = type();
            if (!returnType) {
                error("Expected return type after '->'");
                returnType = std::make_unique<NamedTypeExpr>("void", makeRange(previous_));
            }
        }
    } else {
        // Default return type is void
        returnType = std::make_unique<NamedTypeExpr>("void", makeRange(previous_));
    }
    
    // Parse operator body
    std::unique_ptr<Stmt> body;
    
    // Parse the body as a block statement
    if (match(lexer::TokenType::LEFT_BRACE)) {
        // Set function body flag
        bool oldFunctionBody = inFunctionBody_;
        inFunctionBody_ = true;
        
        std::vector<std::unique_ptr<Stmt>> statements;
        
        while (!check(lexer::TokenType::RIGHT_BRACE) && 
               !check(lexer::TokenType::END_OF_FILE)) {
            
            // Try to parse variable declarations
            if (check(lexer::TokenType::IDENTIFIER)) {
                // Look ahead to see if this is a variable declaration
                lexer::Token typeToken = current_;
                advance(); // Consume possible type name
                
                if (check(lexer::TokenType::IDENTIFIER)) {
                    // Likely a variable declaration
                    lexer::Token nameToken = current_;
                    advance(); // Consume variable name
                    
                    // Create type expression
                    auto typeExpr = std::make_unique<NamedTypeExpr>(
                        typeToken.lexeme(),
                        makeRange(typeToken)
                    );
                    
                    // Parse initializer if present
                    std::unique_ptr<Expr> initializer;
                    if (match(lexer::TokenType::EQUAL)) {
                        initializer = expression();
                    }
                    
                    // Consume semicolon
                    consume(lexer::TokenType::SEMICOLON, "Expected ';' after variable declaration");
                    
                    // Create variable statement
                    auto varStmt = std::make_unique<VarStmt>(
                        nameToken,
                        std::move(typeExpr),
                        std::move(initializer),
                        makeRange(typeToken, previous_)
                    );
                    
                    statements.push_back(std::move(varStmt));
                    continue;
                } else {
                    // Not a variable declaration, rewind and continue normal parsing
                    current_ = typeToken;
                }
            }
            
            // Regular statement parsing
            auto stmt = statement();
            if (stmt) {
                statements.push_back(std::move(stmt));
            } else {
                // Skip problematic tokens
                if (!check(lexer::TokenType::RIGHT_BRACE) && 
                    !check(lexer::TokenType::END_OF_FILE)) {
                    advance();
                }
            }
        }
        
        auto endBrace = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after operator body");
        
        // Restore function body flag
        inFunctionBody_ = oldFunctionBody;
        
        body = std::make_unique<BlockStmt>(
            std::move(statements),
            makeRange(start, endBrace)
        );
    } else {
        error("Expected '{' to begin operator body");
        
        // Create empty block as fallback
        body = std::make_unique<BlockStmt>(
            std::vector<std::unique_ptr<Stmt>>{},
            makeRange(previous_)
        );
    }
    
    // Consume optional semicolon after operator definition
    if (check(lexer::TokenType::SEMICOLON)) {
        consume(lexer::TokenType::SEMICOLON, "Expected ';' after operator definition");
    }
    
    return std::make_unique<OperatorDecl>(
        opSymbol,
        std::move(parameters),
        std::move(returnType),
        std::move(body),
        makeRange(start, previous_),
        false // Not a prototype
    );
}

// Parse a template declaration
std::unique_ptr<Decl> Parser::templateDeclaration() {
    auto templateKeyword = previous_;  // 'template' keyword
    
    // Parse template parameters
    consume(lexer::TokenType::LESS, "Expected '<' after 'template'");
    
    std::vector<TemplateDecl::Parameter> parameters;
    
    if (!check(lexer::TokenType::GREATER)) {
        do {
            // Parse parameter name
            auto paramName = consume(lexer::TokenType::IDENTIFIER, "Expected template parameter name");
            
            // Check for parameter type constraint (e.g., <T: Type>)
            std::unique_ptr<TypeExpr> paramType = nullptr;
            if (match(lexer::TokenType::COLON)) {
                auto constraintName = consume(lexer::TokenType::IDENTIFIER, "Expected constraint type after ':'");
                paramType = std::make_unique<NamedTypeExpr>(
                    constraintName.lexeme(),
                    makeRange(constraintName)
                );
                parameters.emplace_back(
                    paramName.lexeme(),
                    TemplateDecl::Parameter::Kind::VALUE,
                    std::move(paramType)
                );
            } else {
                // Type parameter without constraint
                parameters.emplace_back(
                    paramName.lexeme(),
                    TemplateDecl::Parameter::Kind::TYPE
                );
            }
        } while (match(lexer::TokenType::COMMA));
    }
    
    consume(lexer::TokenType::GREATER, "Expected '>' after template parameters");
    
    // Save state for template context
    bool oldTemplateState = inTemplateDeclaration_;
    inTemplateDeclaration_ = true;
    
    // Parse the declaration being templated (should be a function in this case)
    auto declaration = functionDeclaration();
    if (!declaration) {
        error("Expected function declaration after template parameters");
        // Create a placeholder declaration to avoid null pointer
        declaration = std::make_unique<TypeDecl>(
            "placeholder",
            std::make_unique<NamedTypeExpr>("void", makeRange(previous_)),
            makeRange(previous_)
        );
    }
    
    // Restore template state
    inTemplateDeclaration_ = oldTemplateState;
    
    return std::make_unique<TemplateDecl>(
        std::move(parameters),
        std::move(declaration),
        makeRange(templateKeyword, previous_)
    );
}

// Helper to parse template parameters
std::vector<TemplateDecl::Parameter> Parser::parseTemplateParameters() {
    std::vector<TemplateDecl::Parameter> parameters;
    
    consume(lexer::TokenType::LESS, "Expected '<' after 'template'");
    
    if (!check(lexer::TokenType::GREATER)) {
        do {
            // Parse parameter name
            auto paramName = consume(lexer::TokenType::IDENTIFIER, "Expected template parameter name");
            
            // Check for parameter type constraint (e.g., <T: Type>)
            std::unique_ptr<TypeExpr> paramType = nullptr;
            if (match(lexer::TokenType::COLON)) {
                auto constraintName = consume(lexer::TokenType::IDENTIFIER, "Expected constraint type after ':'");
                paramType = std::make_unique<NamedTypeExpr>(
                    constraintName.lexeme(),
                    makeRange(constraintName)
                );
                parameters.emplace_back(
                    paramName.lexeme(),
                    TemplateDecl::Parameter::Kind::VALUE,
                    std::move(paramType)
                );
            } else {
                // Type parameter without constraint
                parameters.emplace_back(
                    paramName.lexeme(),
                    TemplateDecl::Parameter::Kind::TYPE
                );
            }
        } while (match(lexer::TokenType::COMMA));
    }
    
    consume(lexer::TokenType::GREATER, "Expected '>' after template parameters");
    return parameters;
}

// Parse an enum declaration
std::unique_ptr<Decl> Parser::enumDeclaration() {
    // Parse the enum name
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected enum name");
    
    // Parse the enum body
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after enum name");
    
    std::vector<EnumDecl::Member> members;
    
    // Parse enum members until we reach the closing brace
    while (!check(lexer::TokenType::RIGHT_BRACE) && 
           !check(lexer::TokenType::END_OF_FILE)) {
        // Parse member name
        auto memberName = consume(lexer::TokenType::IDENTIFIER, "Expected enum member name");
        
        // Parse member value (optional)
        std::unique_ptr<Expr> value;
        if (match(lexer::TokenType::EQUAL)) {
            value = expression();
            if (!value) {
                error("Expected expression after '='");
            }
        }
        
        // Add the member to our list
        members.emplace_back(memberName.lexeme(), std::move(value));
        
        // Check for comma - it's required between members but optional after the last member
        if (match(lexer::TokenType::COMMA)) {
            // After a comma, there might be another member or we might be at the end
            // If we're at the closing brace, that's fine (trailing comma case)
            if (check(lexer::TokenType::RIGHT_BRACE)) {
                break;
            }
        } else {
            // If there's no comma, we must be at the end
            if (!check(lexer::TokenType::RIGHT_BRACE)) {
                error("Expected ',' or '}' after enum member");
            }
            break;
        }
    }
    
    auto endToken = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after enum body");
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after enum declaration");
    
    return std::make_unique<EnumDecl>(
        name.lexeme(),
        std::move(members),
        makeRange(name, endToken)
    );
}

// Parse a type declaration
std::unique_ptr<Decl> Parser::typeDeclaration() {
    // Parse the type name
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected type name");
    
    // Parse the underlying type
    auto underlyingType = type();
    if (!underlyingType) {
        error("Expected underlying type");
        return nullptr;
    }
    
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after type declaration");
    
    return std::make_unique<TypeDecl>(
        name.lexeme(),
        std::move(underlyingType),
        makeRange(name, previous_)
    );
}

// Parse a data declaration
std::unique_ptr<Decl> Parser::dataDeclaration() {
    // Determine if it's signed or unsigned
    bool isSigned = !check(lexer::TokenType::KEYWORD_UNSIGNED);
    
    // Skip 'signed' or 'unsigned' if present
    if (check(lexer::TokenType::KEYWORD_SIGNED) || check(lexer::TokenType::KEYWORD_UNSIGNED)) {
        advance();
    }
    
    // Parse 'data' keyword if not already consumed
    if (!previous_.is(lexer::TokenType::KEYWORD_DATA)) {
        consume(lexer::TokenType::KEYWORD_DATA, "Expected 'data' keyword");
    }
    
    // Parse the bit size
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after 'data'");
    
    // Parse the size expression
    auto sizeToken = consume(lexer::TokenType::INTEGER_LITERAL, "Expected bit size");
    int64_t bits = sizeToken.intValue();
    
    consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after bit size");
    
    // Parse alignment if present
    std::optional<size_t> alignment = parseAlignmentAttribute();
    
    // Check for array syntax
    bool isArray = false;
    std::unique_ptr<Expr> arraySizeExpr;
    
    if (match(lexer::TokenType::LEFT_BRACKET)) {
        isArray = true;
        // Check if there's a size expression or an empty bracket for dynamic array
        if (!check(lexer::TokenType::RIGHT_BRACKET)) {
            arraySizeExpr = expression();
        }
        consume(lexer::TokenType::RIGHT_BRACKET, "Expected ']' after array size");
    }
    
    // Parse the type name
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected data type name");
    
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after data declaration");
    
    // Check if this is a volatile data type
    bool isVolatile = false;
    if (match(lexer::TokenType::KEYWORD_VOLATILE)) {
        isVolatile = true;
    }
    
    // Create the data declaration
    if (isArray) {
        // Create a base data type
        auto dataType = std::make_unique<DataTypeExpr>(
            bits,
            isSigned,
            makeRange(previous_),
            alignment,
            isVolatile
        );
        
        // Create an array type that uses the data type as element type
        auto arrayType = std::make_unique<ArrayTypeExpr>(
            std::move(dataType),
            std::move(arraySizeExpr),
            makeRange(previous_)
        );
        
        // Create a type declaration
        return std::make_unique<TypeDecl>(
            name.lexeme(),
            std::move(arrayType),
            makeRange(name, previous_)
        );
    } else {
        // Simple data type declaration
        return std::make_unique<DataDecl>(
            name.lexeme(),
            bits,
            isSigned,
makeRange(previous_),
            alignment,
            isVolatile
        );
    }
}

// Parse an ASM block declaration
std::unique_ptr<Decl> Parser::asmDeclaration() {
    auto start = previous_;  // 'asm' keyword
    
    // Parse the ASM block
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after 'asm'");
    
    // Collect the ASM code as a string
    std::stringstream asmCode;
    
    // Track nested braces
    int braceLevel = 1;
    
    // Continue until we find the matching closing brace
    while (braceLevel > 0 && !check(lexer::TokenType::END_OF_FILE)) {
        if (check(lexer::TokenType::LEFT_BRACE)) {
            braceLevel++;
        } else if (check(lexer::TokenType::RIGHT_BRACE)) {
            braceLevel--;
            if (braceLevel == 0) {
                break;  // Found the matching closing brace
            }
        }
        
        // Add the current token's lexeme to the ASM code
        // Add a space to preserve token separation
        if (asmCode.tellp() > 0) {
            asmCode << " ";
        }
        asmCode << current_.lexeme();
        
        // Move to the next token
        advance();
    }
    
    auto endToken = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after ASM block");
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after ASM block");
    
    return std::make_unique<AsmDecl>(
        asmCode.str(),
        makeRange(start, endToken)
    );
}

// Parse a section declaration
std::unique_ptr<Decl> Parser::sectionDeclaration() {
    auto start = previous_;  // 'section' keyword
    
    // Parse section name in parentheses
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'section'");
    auto sectionNameToken = consume(lexer::TokenType::CHAR_LITERAL, "Expected section name as string literal");
    std::string_view sectionName = sectionNameToken.stringValue();
    consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after section name");
    
    // Parse section attribute (e.g., .rodata)
    SectionDecl::Attribute attribute = parseSectionAttribute();
    
    // Parse address expression if present
    std::unique_ptr<Expr> addressExpr = nullptr;
    if (match(lexer::TokenType::KEYWORD_ADDRESS)) {
        addressExpr = parseAddressSpecifier();
    }
    
    // Parse the declaration being sectioned
    auto innerDecl = declaration();
    if (!innerDecl) {
        error("Expected declaration after section attribute");
        // Create a placeholder to avoid null pointer
        innerDecl = std::make_unique<TypeDecl>(
            "placeholder",
            std::make_unique<NamedTypeExpr>("void", makeRange(previous_)),
            makeRange(previous_)
        );
    }
    
    return std::make_unique<SectionDecl>(
        sectionName,
        attribute,
        std::move(innerDecl),
        std::move(addressExpr),
        makeRange(start, previous_)
    );
}

// Parse a section attribute (e.g., .rodata)
SectionDecl::Attribute Parser::parseSectionAttribute() {
    if (match(lexer::TokenType::DOT)) {
        // Get the attribute name
        auto attrName = consume(lexer::TokenType::IDENTIFIER, "Expected attribute name after '.'");
        
        // Map to the appropriate attribute enum value
        std::string_view name = attrName.lexeme();
        if (name == "rodata") {
            return SectionDecl::Attribute::RODATA;
        } else if (name == "rwdata") {
            return SectionDecl::Attribute::RWDATA;
        } else if (name == "exec") {
            return SectionDecl::Attribute::EXEC;
        } else if (name == "noinit") {
            return SectionDecl::Attribute::NOINIT;
        } else if (name == "persist") {
            return SectionDecl::Attribute::PERSIST;
        } else {
            error("Unknown section attribute: " + std::string(name));
        }
    }
    
    // Default attribute if none specified
    return SectionDecl::Attribute::NONE;
}

// Parse an address specifier (address<0xABCD>)
std::unique_ptr<Expr> Parser::parseAddressSpecifier() {
    auto start = previous_;  // 'address' keyword
    
    consume(lexer::TokenType::LESS, "Expected '<' after 'address'");
    
    // Parse the address value (usually a hex literal)
    auto addressExpr = expression();
    if (!addressExpr) {
        error("Expected address expression");
        // Create a default address expression as fallback
        addressExpr = std::make_unique<LiteralExpr>(
            lexer::Token(lexer::TokenType::INTEGER_LITERAL, "0", start.start(), start.end()),
            static_cast<int64_t>(0)
        );
    }
    
    consume(lexer::TokenType::GREATER, "Expected '>' after address value");
    
    return std::make_unique<AddressOfExpr>(
        std::move(addressExpr),
        makeRange(start, previous_)
    );
}

// Parse an alignment attribute (align{N})
std::optional<size_t> Parser::parseAlignmentAttribute() {
    if (match(lexer::TokenType::KEYWORD_ALIGN)) {
        consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after 'align'");
        auto sizeToken = consume(lexer::TokenType::INTEGER_LITERAL, "Expected alignment size");
        consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after alignment size");
        
        return static_cast<size_t>(sizeToken.intValue());
    }
    
    return std::nullopt;
}

// Parse a statement
std::unique_ptr<Stmt> Parser::statement() {
    // Save current token for potential backtracking
    auto startToken = current_;
    
    // Handle statements that start with keywords
    if (match(lexer::TokenType::KEYWORD_IF)) return ifStatement();
    if (match(lexer::TokenType::KEYWORD_DO)) return doWhileStatement();
    if (match(lexer::TokenType::KEYWORD_WHILE)) return whileStatement();
    if (match(lexer::TokenType::KEYWORD_FOR)) return forStatement();
    if (match(lexer::TokenType::KEYWORD_RETURN)) return returnStatement();
    if (match(lexer::TokenType::KEYWORD_BREAK)) return breakStatement();
    if (match(lexer::TokenType::KEYWORD_CONTINUE)) return continueStatement();
    if (match(lexer::TokenType::KEYWORD_THROW)) return throwStatement();
    if (match(lexer::TokenType::KEYWORD_TRY)) return tryStatement();
    if (match(lexer::TokenType::KEYWORD_SWITCH)) return switchStatement();
    if (match(lexer::TokenType::KEYWORD_ASSERT)) return assertStatement();
    
    // Handle block statements
    if (match(lexer::TokenType::LEFT_BRACE)) {
        if (inControlStructure_ || inFunctionBody_) {
            return blockStatement();
        } else {
            previous_ = startToken; // Reset previous_ to properly track range
            return anonymousBlockStatement();
        }
    }
    
    // Handle empty statements
    if (match(lexer::TokenType::SEMICOLON)) {
        // Empty statement
        return std::make_unique<ExprStmt>(nullptr, makeRange(previous_));
    }
    
    // If current token is an identifier, try to parse as identifier statement
    if (check(lexer::TokenType::IDENTIFIER)) {
        auto identStmt = identifierStatement();
        if (identStmt) {
            return identStmt;
        }
    }
    
    // Try parsing as expression statement
    auto exprStmt = expressionStatement();
    if (exprStmt) {
        return exprStmt;
    }
    
    // If we couldn't parse a statement and we're not at the end
    // of a block or the file, force advancement to prevent infinite loops
    if (!check(lexer::TokenType::END_OF_FILE) && 
        !check(lexer::TokenType::RIGHT_BRACE)) {
        error("Expected statement");
        advance();
    }
    
    return nullptr;
}

// Parse an assert statement
std::unique_ptr<Stmt> Parser::assertStatement() {
    auto start = previous_;  // 'assert' keyword
    
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'assert'");
    
    // Parse the condition expression
    auto condition = expression();
    if (!condition) {
        error("Expected condition in assert statement");
        // Create a default true condition as fallback
        auto trueToken = lexer::Token(
            lexer::TokenType::KEYWORD_TRUE, 
            "true", 
            start.start(), 
            start.end()
        );
        condition = std::make_unique<LiteralExpr>(trueToken, true);
    }
    
    // Parse the optional error message
    std::unique_ptr<Expr> message = nullptr;
    if (match(lexer::TokenType::COMMA)) {
        message = expression();
        if (!message) {
            error("Expected error message after comma in assert statement");
        }
    }
    
    consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after assert condition");
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after assert statement");
    
    // Create the assert statement as a special form of if statement with throw
    auto conditionCheck = std::make_unique<UnaryExpr>(
        lexer::Token(lexer::TokenType::EXCLAMATION, "!", start.start(), start.end()),
        std::move(condition),
        true,  // prefix
        makeRange(start, previous_)
    );
    
    // Create the throw statement for the assertion failure
    std::unique_ptr<Expr> throwMessage;
    if (message) {
        throwMessage = std::move(message);
    } else {
        // Default error message
        auto defaultMsg = lexer::Token(
            lexer::TokenType::CHAR_LITERAL, 
            "\"Assertion failed\"", 
            start.start(), 
            start.end()
        );
        throwMessage = std::make_unique<LiteralExpr>(
            defaultMsg,
            std::string("Assertion failed")
        );
    }
    
    auto throwStmt = std::make_unique<ThrowStmt>(
        start,  // use assert token for throw
        std::move(throwMessage),
        nullptr,  // no additional body
        makeRange(start, previous_)
    );
    
    // Create the if statement that will throw on assertion failure
    return std::make_unique<IfStmt>(
        std::move(conditionCheck),
        std::move(throwStmt),
        nullptr,  // no else branch
        makeRange(start, previous_)
    );
}

// Parse a statement starting with an identifier
std::unique_ptr<Stmt> Parser::identifierStatement() {
    // Only proceed if we're looking at an identifier
    if (!check(lexer::TokenType::IDENTIFIER)) {
        return nullptr;
    }

    // Save the current position for potential backtracking
    auto savePos = current_;
    
    // Don't advance yet - just check what comes after the identifier
    // This is a simplified approach that doesn't try to parse complex declarations
    // We'll let expressionStatement handle assignments
    
    // For now, let's not try to handle identifier statements at all
    // and let expressionStatement handle everything
    return nullptr;
}

// Parse a data type statement (data{32} primitiveName;)
std::unique_ptr<Stmt> Parser::dataTypeStatement() {
    auto startToken = previous_; // Save the data/signed/unsigned token
    bool isSigned = previous_.is(lexer::TokenType::KEYWORD_SIGNED);
    
    // If we have signed/unsigned but not data, consume the data keyword
    if (!previous_.is(lexer::TokenType::KEYWORD_DATA)) {
        consume(lexer::TokenType::KEYWORD_DATA, "Expected 'data' keyword");
    }
    
    // Parse the bit width specification
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after 'data'");
    auto sizeToken = consume(lexer::TokenType::INTEGER_LITERAL, "Expected bit length as INTEGER_LITERAL");
    int64_t bits = sizeToken.intValue();
    consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after bit size");
    
    // Parse primitive type name
    auto typeName = consume(lexer::TokenType::IDENTIFIER, "Expected primitive datatype name after bit length");
    
    // Create the data declaration
    auto dataDecl = std::make_unique<DataDecl>(
        typeName.lexeme(),
        bits,
        isSigned,
        makeRange(startToken, previous_)
    );
    
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after datatype declaration statement");
    
    // Create a decl statement with the data declaration
    return std::make_unique<DeclStmt>(std::move(dataDecl), makeRange(startToken, previous_));
}

// Parse an expression statement
std::unique_ptr<Stmt> Parser::expressionStatement() {
    auto startToken = current_;
    
    // Debug output for line 77
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77: expressionStatement() called, current token: " << current_.toString() << std::endl;
    }
    
    // Parse the expression using the expression() function,
    // which will delegate to assignment() for handling assignments
    auto expr = expression();
    if (!expr) {
        if (current_.start().line == 77) {
            std::cout << "DEBUG LINE 77: Failed to parse expression, current token: " << current_.toString() << std::endl;
        }
        error("Expected expression");
        return nullptr;
    }
    
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77: Parsed expression successfully, current token: " << current_.toString() << std::endl;
    }
    
    // Check if we have a semicolon
    if (!check(lexer::TokenType::SEMICOLON)) {
        if (current_.start().line == 77) {
            std::cout << "DEBUG LINE 77: No semicolon found, current token: " << current_.toString() << std::endl;
        }
        error("Expected ';' after expression");
        return nullptr;
    }
    
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after expression");
    
    return std::make_unique<ExprStmt>(std::move(expr), makeRange(startToken, previous_));
}

// Parse a block statement
std::unique_ptr<Stmt> Parser::blockStatement() {
    auto start = previous_;  // Should be '{'
    
    std::vector<std::unique_ptr<Stmt>> statements;
    
    // Parse statements until we hit a closing brace
    while (!check(lexer::TokenType::RIGHT_BRACE) && 
           !check(lexer::TokenType::END_OF_FILE)) {
        
        // Parse any type of statement
        auto stmt = statement();
        
        if (stmt) {
            statements.push_back(std::move(stmt));
        } else {
            // If we failed to parse a statement but we're at a right brace,
            // that's actually ok - it means we've reached the end of the block
            if (check(lexer::TokenType::RIGHT_BRACE)) {
                break;
            }
            
            // Skip one token to prevent infinite loops
            if (!check(lexer::TokenType::RIGHT_BRACE) && 
                !check(lexer::TokenType::END_OF_FILE)) {
                advance();
                // After advancing, check if we're at a right brace again
                if (check(lexer::TokenType::RIGHT_BRACE)) {
                    break;
                }
            }
        }
    }
    
    auto end = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after block");
    
    return std::make_unique<BlockStmt>(
        std::move(statements),
        makeRange(start, end)
    );
}

// Parse anonymous block statements
std::unique_ptr<Stmt> Parser::anonymousBlockStatement() {
    auto start = previous_;  // Should be '{'
    
    std::vector<std::unique_ptr<Stmt>> statements;
    
    // Parse statements until we reach the closing brace
    while (!check(lexer::TokenType::RIGHT_BRACE) && 
           !check(lexer::TokenType::END_OF_FILE)) {
        
        // Handle function declarations
        if (check(lexer::TokenType::KEYWORD_DEF)) {
            auto funcDecl = functionDeclaration();
            if (funcDecl) {
                // Convert the function declaration to a statement
                statements.push_back(std::make_unique<DeclStmt>(
                    std::move(funcDecl),
                    funcDecl->range
                ));
                continue;
            }
        }
        
        // Parse a regular statement
        auto stmt = statement();
        
        if (stmt) {
            statements.push_back(std::move(stmt));
        } else {
            // Force advancement to prevent getting stuck
            error("Expected statement in anonymous block");
            advance();
            synchronize();
        }
    }
    
    // Consume closing brace
    auto end = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' to close anonymous block");
    
    // Consume semicolon after block
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after anonymous block");
    
    return std::make_unique<BlockStmt>(
        std::move(statements),
        makeRange(start, end)
    );
}

// Parse an if statement
std::unique_ptr<Stmt> Parser::ifStatement() {
    auto start = previous_;  // 'if' keyword
    
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'if'");
    
    // Parse the condition expression
    auto condition = expression();
    if (!condition) {
        error("Expected condition expression in if statement");
        synchronize();
        return nullptr;
    }
    
    consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after condition");
    
    // Set control structure flag
    bool oldControlStructure = inControlStructure_;
    inControlStructure_ = true;
    
    // Parse then branch
    std::unique_ptr<Stmt> thenBranch;
    
    if (match(lexer::TokenType::LEFT_BRACE)) {
        // Create a simple block statement directly
        thenBranch = blockStatement();
    } else {
        thenBranch = statement();
    }
    
    if (!thenBranch) {
        error("Expected statement after if condition");
        // Create a dummy block to avoid null pointer
        thenBranch = std::make_unique<BlockStmt>(
            std::vector<std::unique_ptr<Stmt>>{},
            makeRange(previous_)
        );
    }
    
    // Parse else branch
    std::unique_ptr<Stmt> elseBranch;
    
    if (match(lexer::TokenType::KEYWORD_ELSE)) {
        if (match(lexer::TokenType::LEFT_BRACE)) {
            // Create a simple block statement directly for else branch
            elseBranch = blockStatement();
        } else if (check(lexer::TokenType::KEYWORD_IF)) {
            // This is an else-if
            elseBranch = statement();
        } else {
            elseBranch = statement();
        }
    }
    
    // Restore control structure flag
    inControlStructure_ = oldControlStructure;
    
    return std::make_unique<IfStmt>(
        std::move(condition),
        std::move(thenBranch),
        std::move(elseBranch),
        makeRange(start, previous_)
    );
}

// Parse a do-while statement
std::unique_ptr<Stmt> Parser::doWhileStatement() {
    auto start = previous_;  // 'do' keyword
    
    // Set control structure flag
    bool oldControlStructure = inControlStructure_;
    inControlStructure_ = true;
    
    // Parse body
    std::unique_ptr<Stmt> body;
    if (match(lexer::TokenType::LEFT_BRACE)) {
        // Block statement
        body = blockStatement();
    } else {
        // Single statement
        body = statement();
        if (!body) {
            // Create empty block to avoid null pointer
            body = std::make_unique<BlockStmt>(
                std::vector<std::unique_ptr<Stmt>>{},
                makeRange(previous_)
            );
        }
    }
    
    // Parse 'while' and condition
    consume(lexer::TokenType::KEYWORD_WHILE, "Expected 'while' after do block");
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'while'");
    
    auto condition = expression();
    if (!condition) {
        // Default to true condition if parse fails
        auto trueToken = lexer::Token(
            lexer::TokenType::KEYWORD_TRUE, 
            "true", 
            previous_.start(), 
            previous_.end()
        );
        condition = std::make_unique<LiteralExpr>(trueToken, true);
    }
    
    consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after while condition");
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after do-while statement");
    
    // Restore control structure flag
    inControlStructure_ = oldControlStructure;
    
    // Create a specialized DoWhileStmt or adapt WhileStmt
    // You may need to add a DoWhileStmt class to your AST,
    // or use WhileStmt with a flag indicating it's a do-while loop
    return std::make_unique<WhileStmt>(
        std::move(condition),
        std::move(body),
        makeRange(start, previous_)
    );
}

// Parse a while statement
std::unique_ptr<Stmt> Parser::whileStatement() {
    auto start = previous_;  // 'while' keyword
    
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'while'");
    
    // Parse condition expression - special handling for logical operators
    std::unique_ptr<Expr> condition;
    
    // Track the starting position for error recovery
    auto condStart = current_;
    
    // Check for complex logical expressions
    try {
        condition = expression();
        
        if (!condition) {
            error("Expected condition expression in while statement");
            // Create a default true condition for error recovery
            condition = std::make_unique<LiteralExpr>(
                lexer::Token(lexer::TokenType::KEYWORD_TRUE, "true", 
                           condStart.start(), condStart.end()),
                true
            );
        }
    } catch (const std::exception& e) {
        error(std::string("Error in while condition: ") + e.what());
        
        // Create a default true condition for error recovery
        condition = std::make_unique<LiteralExpr>(
            lexer::Token(lexer::TokenType::KEYWORD_TRUE, "true", 
                       condStart.start(), condStart.end()),
            true
        );
        
        // Try to synchronize by finding the closing parenthesis
        while (!check(lexer::TokenType::RIGHT_PAREN) && 
               !check(lexer::TokenType::END_OF_FILE)) {
            advance();
        }
    }
    
    consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after while condition");
    
    // Set flag to indicate we're in a control structure
    bool oldControl = inControlStructure_;
    inControlStructure_ = true;
    
    // Parse the body
    std::unique_ptr<Stmt> body;
    
    if (match(lexer::TokenType::LEFT_BRACE)) {
        body = blockStatement();
    } else {
        // Single statement body
        body = statement();
        
        if (!body) {
            error("Expected statement for while loop body");
            
            // Create an empty block as fallback
            body = std::make_unique<BlockStmt>(
                std::vector<std::unique_ptr<Stmt>>{},
                makeRange(previous_)
            );
        }
    }
    
    // Restore control structure flag
    inControlStructure_ = oldControl;
    
    return std::make_unique<WhileStmt>(
        std::move(condition),
        std::move(body),
        makeRange(start, previous_)
    );
}

// Parse a for statement
std::unique_ptr<Stmt> Parser::forStatement() {
    auto start = previous_;  // 'for' keyword
    
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'for'");
    
    // Parse initializer (first expression)
    std::unique_ptr<Stmt> initializer = nullptr;
    
    if (!check(lexer::TokenType::SEMICOLON)) {
        // Check if the initializer is a variable declaration (int x = 5)
        if (check(lexer::TokenType::IDENTIFIER)) {
            auto typeToken = current_;
            advance(); // Consume possible type name
            
            // Check if this is a variable declaration
            if (check(lexer::TokenType::IDENTIFIER)) {
                // This is a variable declaration
                auto nameToken = current_;
                advance(); // Consume name
                
                // Create type expression
                auto typeExpr = std::make_unique<NamedTypeExpr>(
                    typeToken.lexeme(),
                    makeRange(typeToken)
                );
                
                // Parse initializer if present
                std::unique_ptr<Expr> varInitializer = nullptr;
                if (match(lexer::TokenType::EQUAL)) {
                    varInitializer = expression();
                    if (!varInitializer) {
                        error("Expected initializer expression");
                    }
                }
                
                // Create variable statement
                initializer = std::make_unique<VarStmt>(
                    nameToken,
                    std::move(typeExpr),
                    std::move(varInitializer),
                    makeRange(typeToken, previous_)
                );
            } else {
                // Not a variable declaration, rewind and parse as expression
                current_ = typeToken;
                auto expr = expression();
                if (expr) {
                    initializer = std::make_unique<ExprStmt>(
                        std::move(expr),
                        makeRange(start, previous_)
                    );
                }
            }
        } else {
            // Regular expression initializer
            auto expr = expression();
            if (expr) {
                initializer = std::make_unique<ExprStmt>(
                    std::move(expr),
                    makeRange(start, previous_)
                );
            }
        }
    }
    
    // Consume the first semicolon
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after for initializer");
    
    // Parse condition (second expression)
    std::unique_ptr<Expr> condition = nullptr;
    if (!check(lexer::TokenType::SEMICOLON)) {
        condition = expression();
        if (!condition) {
            error("Expected condition expression or ';' in for loop");
        }
    }
    
    // Consume the second semicolon
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after for condition");
    
    // Parse increment (third expression)
    std::unique_ptr<Expr> increment = nullptr;
    if (!check(lexer::TokenType::RIGHT_PAREN)) {
        increment = expression();
        if (!increment) {
            error("Expected increment expression or ')' in for loop");
        }
    }
    
    // Consume the closing parenthesis
    consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after for clauses");
    
    // Set flag to indicate we're in a control structure
    bool oldInControl = inControlStructure_;
    inControlStructure_ = true;
    
    // Parse body
    std::unique_ptr<Stmt> body;
    
    if (match(lexer::TokenType::LEFT_BRACE)) {
        // Parse the body as a block statement
        body = blockStatement();
    } else {
        // Single statement
        body = statement();
        
        if (!body) {
            error("Expected statement for for loop body");
            
            // Create an empty block as fallback
            body = std::make_unique<BlockStmt>(
                std::vector<std::unique_ptr<Stmt>>{},
                makeRange(previous_)
            );
        }
    }
    
    // Restore control structure flag
    inControlStructure_ = oldInControl;
    
    return std::make_unique<ForStmt>(
        std::move(initializer),
        std::move(condition),
        std::move(increment),
        std::move(body),
        makeRange(start, previous_)
    );
}

// Parse a return statement
std::unique_ptr<Stmt> Parser::returnStatement() {
    auto start = previous_;  // 'return' keyword
    
    // Parse return value if present
    std::unique_ptr<Expr> value = nullptr;
    if (!check(lexer::TokenType::SEMICOLON)) {
        value = expression();
        if (!value) {
            error("Expected expression after 'return'");
        }
    }
    
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after return statement");
    
    return std::make_unique<ReturnStmt>(
        start,
        std::move(value),
        makeRange(start, previous_)
    );
}

// Parse a break statement
std::unique_ptr<Stmt> Parser::breakStatement() {
    auto keyword = previous_;  // 'break' keyword
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after break statement");
    
    return std::make_unique<BreakStmt>(
        keyword,
        makeRange(keyword, previous_)
    );
}

// Parse a continue statement
std::unique_ptr<Stmt> Parser::continueStatement() {
    auto keyword = previous_;  // 'continue' keyword
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after continue statement");
    
    return std::make_unique<ContinueStmt>(
        keyword,
        makeRange(keyword, previous_)
    );
}

// Parse a throw statement
std::unique_ptr<Stmt> Parser::throwStatement() {
    auto start = previous_; // 'throw' keyword
    
    // Parse the message (optional)
    std::unique_ptr<Expr> message;
    if (match(lexer::TokenType::LEFT_PAREN)) {
        // If there's a message, parse it
        if (!check(lexer::TokenType::RIGHT_PAREN)) {
            message = expression();
            if (!message) {
                error("Expected expression for throw message");
            }
        }
        
        consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after throw message");
    }
    
    // Parse the optional code block
    std::unique_ptr<Stmt> body;
    if (match(lexer::TokenType::LEFT_BRACE)) {
        // Parse the code block
        body = blockStatement();
    }
    
    // Consume the semicolon
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after throw statement");
    
    // Create and return the throw statement
    return std::make_unique<ThrowStmt>(
        start,
        std::move(message),
        std::move(body),
        makeRange(start, previous_)
    );
}

// Parse a try-catch statement
std::unique_ptr<Stmt> Parser::tryStatement() {
    auto start = previous_;  // 'try' keyword
    
    // Parse try block
    std::unique_ptr<Stmt> tryBlock;
    if (match(lexer::TokenType::LEFT_BRACE)) {
        // Parse the try block as a normal block statement
        tryBlock = blockStatement();
    } else {
        error("Expected '{' after 'try'");
        // Create an empty block as fallback
        tryBlock = std::make_unique<BlockStmt>(
            std::vector<std::unique_ptr<Stmt>>{},
            makeRange(start)
        );
    }
    
    // Parse catch clauses
    std::vector<TryStmt::CatchClause> catchClauses;
    
    while (match(lexer::TokenType::KEYWORD_CATCH)) {
        auto catchToken = previous_;
        
        // Parse exception type (optional)
        std::unique_ptr<TypeExpr> exceptionType;
        
        if (match(lexer::TokenType::LEFT_PAREN)) {
            // Check if there's an actual type or if it's an empty catch
            if (!check(lexer::TokenType::RIGHT_PAREN)) {
                // Parse the exception type
                exceptionType = type();
                if (!exceptionType) {
                    error("Expected type in catch clause");
                }
            }
            
            consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after catch type");
        } else {
            error("Expected '(' after 'catch'");
        }
        
        // Parse catch handler block
        std::unique_ptr<Stmt> handler;
        
        if (match(lexer::TokenType::LEFT_BRACE)) {
            // Parse the catch block
            handler = blockStatement();
        } else {
            error("Expected '{' after catch parameters");
            // Create an empty block as fallback
            handler = std::make_unique<BlockStmt>(
                std::vector<std::unique_ptr<Stmt>>{},
                makeRange(catchToken)
            );
        }
        
        catchClauses.emplace_back(std::move(exceptionType), std::move(handler));
    }
    
    if (catchClauses.empty()) {
        error("Expected at least one catch clause");
    }
    
    // Consume the semicolon at the end of the try-catch statement
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after try-catch statement");
    
    return std::make_unique<TryStmt>(
        std::move(tryBlock),
        std::move(catchClauses),
        makeRange(start, previous_)
    );
}

// Parse a switch statement
std::unique_ptr<Stmt> Parser::switchStatement() {
    auto start = previous_;  // 'switch' keyword
    
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'switch'");
    auto value = expression();
    if (!value) {
        error("Expected expression in switch statement");
        synchronize();
        return nullptr;
    }
    consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after switch value");
    
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after switch value");
    
    std::vector<SwitchStmt::CaseClause> cases;
    std::unique_ptr<Stmt> defaultCase;
    bool hasDefaultCase = false;
    
    // Process case clauses
    while (!check(lexer::TokenType::RIGHT_BRACE) && 
           !check(lexer::TokenType::END_OF_FILE)) {
        
        if (match(lexer::TokenType::KEYWORD_CASE)) {
            // Parse pattern with parentheses
            consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'case'");
            
            // Check if this is the default case
            bool isDefaultCase = check(lexer::TokenType::KEYWORD_DEFAULT);
            std::unique_ptr<Expr> pattern;
            
            if (isDefaultCase) {
                // This is the default case with keyword 'default'
                advance(); // Consume 'default'
                
                if (hasDefaultCase) {
                    error("Multiple default cases in switch statement");
                }
                hasDefaultCase = true;
            } else {
                // Regular case with pattern expression
                pattern = expression();
                if (!pattern) {
                    error("Expected pattern expression in case");
                    synchronize();
                    continue;
                }
            }
            
            consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after case pattern");
            
            // Parse case body
            consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after case pattern");
            
            // Parse statements inside the case body
            auto body = blockStatement();
            
            consume(lexer::TokenType::SEMICOLON, "Expected ';' after case block");
            
            if (isDefaultCase) {
                defaultCase = std::move(body);
            } else {
                cases.emplace_back(std::move(pattern), std::move(body));
            }
        } else {
            error("Expected 'case' in switch statement");
            advance(); // Skip problematic token
        }
    }
    
    // Check if there was a default case
    if (!hasDefaultCase) {
        error("Switch statement must have a default case");
    }
    
    auto end = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after switch statement");
    consume(lexer::TokenType::SEMICOLON, "Expected ';' after switch statement");
    
    return std::make_unique<SwitchStmt>(
        std::move(value),
        std::move(cases),
        std::move(defaultCase),
        makeRange(start, end)
    );
}

// Parse a variable statement
std::unique_ptr<Stmt> Parser::variableStatement() {
    // Save the start position
    auto startToken = current_;
    
    // Parse variable type 
    std::string typeName;
    auto typeToken = current_;
    if (check(lexer::TokenType::IDENTIFIER)) {
        typeName = std::string(current_.lexeme());
        advance(); // Consume the type name
        
        // Handle qualified types (e.g., Flux.Integer)
        if (match(lexer::TokenType::DOT)) {
            if (check(lexer::TokenType::IDENTIFIER)) {
                typeName += "." + std::string(current_.lexeme());
                advance(); // Consume the second part of the qualified name
            } else {
                error("Expected identifier after '.' in qualified type name");
            }
        }
    } else {
        error("Expected type name for variable declaration");
        return nullptr;
    }
    
    // Check for variable name
    if (!check(lexer::TokenType::IDENTIFIER)) {
        // Not a variable declaration
        current_ = startToken; // Rewind
        return nullptr;
    }
    
    // Parse variable name
    auto nameToken = current_;
    advance(); // Consume variable name
    
    // Create type expression
    auto typeExpr = std::make_unique<NamedTypeExpr>(
        typeName,
        makeRange(typeToken, previous_)
    );
    
    // Parse initializer (optional)
    std::unique_ptr<Expr> initializer = nullptr;
    if (match(lexer::TokenType::EQUAL)) {
        initializer = expression();
        if (!initializer) {
            error("Expected initializer expression");
        }
    }
    
    // Manually check and consume semicolon
    if (check(lexer::TokenType::SEMICOLON)) {
        advance(); // Consume semicolon
    } else {
        error("Expected ';' after variable declaration");
        // Don't fail catastrophically - continue parsing
    }
    
    // Create and return the variable statement
    return std::make_unique<VarStmt>(
        nameToken,
        std::move(typeExpr),
        std::move(initializer),
        makeRange(startToken, previous_)
    );
}

// Parse an expression
std::unique_ptr<Expr> Parser::expression() {
    try {
        return assignment();
    } catch (const std::exception& e) {
        error(std::string("Error parsing expression: ") + e.what());
        synchronize();
        return nullptr;
    }
}

// Parse an assignment expression
std::unique_ptr<Expr> Parser::assignment() {
    // Parse ternary expressions first (lower precedence than assignment)
    auto expr = ternary();
    if (!expr) return nullptr;
    
    // Debug for line 77
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77 ASSIGNMENT: Parsed left side, current token: " << current_.toString() << std::endl;
    }
    
    // Check for assignment operators (including compound assignment)
    if (match({
        lexer::TokenType::EQUAL,
        lexer::TokenType::PLUS_EQUAL,
        lexer::TokenType::MINUS_EQUAL,
        lexer::TokenType::ASTERISK_EQUAL,
        lexer::TokenType::SLASH_EQUAL,
        lexer::TokenType::PERCENT_EQUAL,
        lexer::TokenType::AMPERSAND_EQUAL,
        lexer::TokenType::PIPE_EQUAL,
        lexer::TokenType::CARET_EQUAL,
        lexer::TokenType::LESS_LESS_EQUAL,
        lexer::TokenType::GREATER_GREATER_EQUAL,
        lexer::TokenType::DOUBLE_ASTERISK_EQUAL
    })) {
        auto opToken = previous_;
        
        if (current_.start().line == 77 || previous_.start().line == 77) {
            std::cout << "DEBUG LINE 77 ASSIGNMENT: Found assignment operator: " << opToken.toString() << std::endl;
            std::cout << "DEBUG LINE 77 ASSIGNMENT: About to parse right side, current token: " << current_.toString() << std::endl;
        }
        
        auto value = assignment();  // Right-associative
        if (!value) {
            if (current_.start().line == 77) {
                std::cout << "DEBUG LINE 77 ASSIGNMENT: Failed to parse right side" << std::endl;
            }
            error("Expected expression after assignment operator");
            return expr;
        }
        
        if (previous_.start().line == 77 || current_.start().line == 77) {
            std::cout << "DEBUG LINE 77 ASSIGNMENT: Successfully parsed assignment, current token: " << current_.toString() << std::endl;
        }
        
        return std::make_unique<AssignExpr>(
            std::move(expr),
            opToken,
            std::move(value),
            makeRange(expr->range.start, value->range.end)
        );
    }
    
    // Debug for line 77
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77 ASSIGNMENT: No assignment operator found, returning ternary result" << std::endl;
    }
    
    // No assignment operator found, just return the ternary expression
    return expr;
}

// Parse a cast expression
std::unique_ptr<Expr> Parser::cast() {
    // For now, just pass through to call() - we'll implement casting differently later
    return call();
}

// Parse a ternary expression
std::unique_ptr<Expr> Parser::ternary() {
    auto expr = logicalOr();
    if (!expr) return nullptr;

    if (match(lexer::TokenType::QUESTION)) {
        auto questionToken = previous_;
        
        // Parse then branch - use assignment for proper precedence
        auto thenExpr = assignment();
        if (!thenExpr) {
            error("Expected expression after '?' in ternary expression");
            return expr;
        }
        
        // Must have colon
        if (!match(lexer::TokenType::COLON)) {
            error("Expected ':' after then branch in ternary expression");
            return expr;
        }
        
        // Parse else branch - use ternary for right-associativity
        auto elseExpr = ternary();
        if (!elseExpr) {
            error("Expected expression after ':' in ternary expression");
            return expr;
        }
        
        return std::make_unique<TernaryExpr>(
            std::move(expr),
            std::move(thenExpr),
            std::move(elseExpr),
            makeRange(expr->range.start, elseExpr->range.end)
        );
    }
    
    return expr;
}

// Parse a logical OR expression
std::unique_ptr<Expr> Parser::logicalOr() {
    auto expr = logicalAnd();
    
    while (match({lexer::TokenType::KEYWORD_OR, lexer::TokenType::PIPE_PIPE})) {
        auto op = previous_;
        auto right = logicalAnd();
        if (!right) {
            error("Expected expression after logical OR operator");
            break;
        }
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(op, previous_)
        );
    }
    
    return expr;
}

// Parse a logical AND expression
std::unique_ptr<Expr> Parser::logicalAnd() {
    auto expr = bitwiseOr();
    
    while (match({lexer::TokenType::KEYWORD_AND, lexer::TokenType::AMPERSAND_AMPERSAND})) {
        auto op = previous_;
        auto right = bitwiseOr();
        if (!right) {
            error("Expected expression after logical AND operator");
            break;
        }
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(op, previous_)
        );
    }
    
    return expr;
}

// Parse a bitwise OR expression
std::unique_ptr<Expr> Parser::bitwiseOr() {
    auto expr = bitwiseXor();
    
    while (match(lexer::TokenType::PIPE)) {
        auto op = previous_;
        
        auto right = bitwiseXor();
        
        if (!right) {
            error("Expected expression after '|'");
            return expr;  // Return what we have so far
        }
        
        // Create the binary expression with proper range tracking
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(expr->range.start, right->range.end)
        );
    }
    
    return expr;
}

// Parse a bitwise XOR expression
std::unique_ptr<Expr> Parser::bitwiseXor() {
    auto expr = bitwiseAnd();
    
    while (match({lexer::TokenType::CARET, lexer::TokenType::KEYWORD_XOR})) {
        auto op = previous_;
        
        // Special handling for xor as function call
        if (op.is(lexer::TokenType::KEYWORD_XOR) && check(lexer::TokenType::LEFT_PAREN)) {
            // Save the xor token for the function expression
            auto xorToken = op;
            
            // Consume opening parenthesis
            consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'xor'");
            
            // Parse arguments
            std::vector<std::unique_ptr<Expr>> arguments;
            
            if (!check(lexer::TokenType::RIGHT_PAREN)) {
                do {
                    // Special handling for boolean literals
                    if (check(lexer::TokenType::KEYWORD_TRUE)) {
                        auto trueToken = current_;
                        advance(); // Consume 'true'
                        arguments.push_back(std::make_unique<LiteralExpr>(trueToken, true));
                    } 
                    else if (check(lexer::TokenType::KEYWORD_FALSE)) {
                        auto falseToken = current_;
                        advance(); // Consume 'false'
                        arguments.push_back(std::make_unique<LiteralExpr>(falseToken, false));
                    }
                    else {
                        // For other expressions, use primary() to avoid recursion
                        auto arg = primary();
                        if (!arg) {
                            error("Expected argument in xor() call");
                            break;
                        }
                        arguments.push_back(std::move(arg));
                    }
                } while (match(lexer::TokenType::COMMA));
            }
            
            // Consume closing parenthesis
            auto closeToken = consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after xor arguments");
            
            // Create a variable expression for the xor function
            auto xorVar = std::make_unique<VariableExpr>(xorToken);
            
            // Create a call expression
            expr = std::make_unique<CallExpr>(
                std::move(xorVar),
                closeToken,
                std::move(arguments),
                makeRange(xorToken, closeToken)
            );
        } else {
            // Normal binary xor operation
            auto right = bitwiseAnd();
            if (!right) {
                error("Expected expression after XOR operator");
                break;
            }
            expr = std::make_unique<BinaryExpr>(
                std::move(expr),
                op,
                std::move(right),
                makeRange(op, previous_)
            );
        }
    }
    
    return expr;
}

// Parse a bitwise AND expression
std::unique_ptr<Expr> Parser::bitwiseAnd() {
    auto expr = equality();
    
    while (match(lexer::TokenType::AMPERSAND)) {
        auto op = previous_;
        auto right = equality();
        if (!right) {
            error("Expected expression after '&'");
            break;
        }
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(op, previous_)
        );
    }
    
    return expr;
}

// Parse an equality expression
std::unique_ptr<Expr> Parser::equality() {
    auto expr = is();
    
    while (match({
        lexer::TokenType::EQUAL_EQUAL, 
        lexer::TokenType::NOT_EQUAL
    })) {
        auto op = previous_;
        auto right = is();
        if (!right) {
            error("Expected expression after equality operator");
            break;
        }
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(op, previous_)
        );
    }
    
    return expr;
}

// Parse an 'is' expression (for type checking)
std::unique_ptr<Expr> Parser::is() {
    auto expr = comparison();
    
    while (match(lexer::TokenType::KEYWORD_IS)) {
        auto op = previous_;
        auto right = comparison();
        if (!right) {
            error("Expected expression after 'is'");
            break;
        }
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(op, previous_)
        );
    }
    
    return expr;
}

// Parse a comparison expression
std::unique_ptr<Expr> Parser::comparison() {
    auto expr = bitShift();
    
    while (match({
        lexer::TokenType::LESS, 
        lexer::TokenType::LESS_EQUAL,
        lexer::TokenType::GREATER,
        lexer::TokenType::GREATER_EQUAL
    })) {
        auto op = previous_;
        auto right = bitShift();
        if (!right) {
            error("Expected expression after comparison operator");
            break;
        }
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(op, previous_)
        );
    }
    
    return expr;
}

// Parse a bit shift expression
std::unique_ptr<Expr> Parser::bitShift() {
    auto expr = term();
    
    while (match({
        lexer::TokenType::LESS_LESS, 
        lexer::TokenType::GREATER_GREATER
    })) {
        auto op = previous_;
        auto right = term();
        if (!right) {
            error("Expected expression after bit shift operator");
            break;
        }
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(op, previous_)
        );
    }
    
    return expr;
}

// Parse a term expression
std::unique_ptr<Expr> Parser::term() {
    auto expr = factor();
    
    while (match({
        lexer::TokenType::PLUS, 
        lexer::TokenType::MINUS
    })) {
        auto op = previous_;
        auto right = factor();
        
        if (!right) {
            error("Expected expression after '" + std::string(op.lexeme()) + "'");
            break;
        }
        
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(expr->range.start, previous_.end())
        );
    }
    
    return expr;
}

// Parse a factor expression
std::unique_ptr<Expr> Parser::factor() {
    auto expr = exponentiation();
    if (!expr) return nullptr;
    
    // Debug for line 77
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77 FACTOR: Starting factor, current token: " << current_.toString() << std::endl;
    }
    
    while (true) {
        // Check for compound assignment operators first to avoid consuming them
        if (check(lexer::TokenType::ASTERISK_EQUAL) ||
            check(lexer::TokenType::SLASH_EQUAL) ||
            check(lexer::TokenType::PERCENT_EQUAL)) {
            // Don't consume these - let assignment() handle them
            if (current_.start().line == 77) {
                std::cout << "DEBUG LINE 77 FACTOR: Found compound assignment operator, breaking: " << current_.toString() << std::endl;
            }
            break;
        }
        
        // Debug for line 77
        if (current_.start().line == 77) {
            std::cout << "DEBUG LINE 77 FACTOR: Checking for operators, current token: " << current_.toString() << std::endl;
        }
        
        // Now check for regular operators
        if (match({
            lexer::TokenType::ASTERISK, 
            lexer::TokenType::SLASH,
            lexer::TokenType::PERCENT
        })) {
            auto op = previous_;
            
            if (current_.start().line == 77 || previous_.start().line == 77) {
                std::cout << "DEBUG LINE 77 FACTOR: Matched operator: " << op.toString() << std::endl;
                std::cout << "DEBUG LINE 77 FACTOR: About to parse right operand, current token: " << current_.toString() << std::endl;
            }
            
            auto right = exponentiation();
            if (!right) {
                error("Expected expression after '" + std::string(op.lexeme()) + "'");
                break;
            }
            
            if (current_.start().line == 77) {
                std::cout << "DEBUG LINE 77 FACTOR: Parsed binary expression, current token: " << current_.toString() << std::endl;
            }
            
            expr = std::make_unique<BinaryExpr>(
                std::move(expr),
                op,
                std::move(right),
                makeRange(expr->range.start, previous_.end())
            );
        } else {
            if (current_.start().line == 77) {
                std::cout << "DEBUG LINE 77 FACTOR: No operator matched, breaking. Current token: " << current_.toString() << std::endl;
            }
            break;
        }
    }
    
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77 FACTOR: Returning from factor, current token: " << current_.toString() << std::endl;
    }
    
    return expr;
}

// Parse an exponentiation expression
std::unique_ptr<Expr> Parser::exponentiation() {
    auto expr = unary();
    
    while (match(lexer::TokenType::DOUBLE_ASTERISK)) {
        auto op = previous_;
        auto right = unary();  // Right associative
        if (!right) {
            error("Expected expression after '**'");
            break;
        }
        expr = std::make_unique<BinaryExpr>(
            std::move(expr),
            op,
            std::move(right),
            makeRange(expr->range.start, previous_.end())
        );
    }
    
    return expr;
}

// Parse a unary expression
std::unique_ptr<Expr> Parser::unary() {
    // Handle 'not' keyword as a unary operator
    if (match(lexer::TokenType::KEYWORD_NOT)) {
        auto notToken = previous_;
        auto operand = unary();
        if (!operand) {
            error("Expected expression after 'not'");
            operand = std::make_unique<LiteralExpr>(
                lexer::Token(lexer::TokenType::KEYWORD_FALSE, "false", 
                           notToken.start(), notToken.end()),
                false
            );
        }
        return std::make_unique<UnaryExpr>(
            notToken,
            std::move(operand),
            true,  // prefix
            makeRange(notToken, previous_)
        );
    }
    
    // Handle standard unary operators
    if (match({
        lexer::TokenType::EXCLAMATION,
        lexer::TokenType::MINUS,
        lexer::TokenType::PLUS,
        lexer::TokenType::TILDE,
        lexer::TokenType::PLUS_PLUS,
        lexer::TokenType::MINUS_MINUS
    })) {
        auto op = previous_;
        auto right = unary();
        if (!right) {
            error("Expected expression after unary operator");
            return nullptr;
        }
        return std::make_unique<UnaryExpr>(
            op,
            std::move(right),
            true,  // prefix
            makeRange(op, previous_)
        );
    }
    
    // Handle address-of operator (@)
    if (match(lexer::TokenType::AT_REF)) {
        auto op = previous_;
        auto right = unary();
        if (!right) {
            error("Expected expression after '@' for address-of");
            return nullptr;
        }
        return std::make_unique<UnaryExpr>(
            op,
            std::move(right),
            true,  // prefix
            makeRange(op, previous_)
        );
    }
    
    // No unary operator found, proceed to postfix
    return postfix();
}

// Parse a postfix expression
std::unique_ptr<Expr> Parser::postfix() {
    auto expr = cast();
    
    if (match({
        lexer::TokenType::PLUS_PLUS,
        lexer::TokenType::MINUS_MINUS,
    })) {
        auto op = previous_;
        return std::make_unique<UnaryExpr>(
            op,
            std::move(expr),
            false,  // postfix
            makeRange(op, previous_)
        );
    }
    
    return expr;
}

// Parse a call expression
std::unique_ptr<Expr> Parser::call() {
    auto expr = primary();
    
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77 CALL: Parsed primary, current token: " << current_.toString() << std::endl;
    }
    
    while (true) {
        if (current_.start().line == 77) {
            std::cout << "DEBUG LINE 77 CALL: In while loop, current token: " << current_.toString() << std::endl;
        }
        
        // Function call
        if (match(lexer::TokenType::LEFT_PAREN)) {
            if (current_.start().line == 77 || previous_.start().line == 77) {
                std::cout << "DEBUG LINE 77 CALL: Matched left paren for function call" << std::endl;
            }
            expr = finishCall(std::move(expr));
        } 
        // Property access
        else if (match(lexer::TokenType::DOT)) {
            if (current_.start().line == 77 || previous_.start().line == 77) {
                std::cout << "DEBUG LINE 77 CALL: Matched dot for property access" << std::endl;
            }
            auto name = consume(lexer::TokenType::IDENTIFIER, "Expected property name after '.'");
            expr = std::make_unique<GetExpr>(
                std::move(expr),
                name,
                makeRange(previous_, name)
            );
        } 
        // Subscript/indexing
        else if (match(lexer::TokenType::LEFT_BRACKET)) {
            if (current_.start().line == 77 || previous_.start().line == 77) {
                std::cout << "DEBUG LINE 77 CALL: Matched left bracket for subscript" << std::endl;
            }
            auto index = expression();
            auto right = consume(lexer::TokenType::RIGHT_BRACKET, "Expected ']' after index");
            expr = std::make_unique<SubscriptExpr>(
                std::move(expr),
                std::move(index),
                makeRange(previous_, right)
            );
        } 
        // No more postfix expressions
        else {
            if (current_.start().line == 77) {
                std::cout << "DEBUG LINE 77 CALL: No postfix matched, breaking. Current token: " << current_.toString() << std::endl;
            }
            break;
        }
    }
    
    if (current_.start().line == 77) {
        std::cout << "DEBUG LINE 77 CALL: Returning from call, current token: " << current_.toString() << std::endl;
    }
    
    return expr;
}

// Parse a primary expression
std::unique_ptr<Expr> Parser::primary() {
    try {
        // Handle literals and keywords
        if (match(lexer::TokenType::KEYWORD_THIS)) {
            return std::make_unique<VariableExpr>(previous_);
        }
        
        if (match(lexer::TokenType::KEYWORD_SUPER)) {
            return std::make_unique<VariableExpr>(previous_);
        }

        if (match(lexer::TokenType::KEYWORD_FALSE)) {
            return std::make_unique<LiteralExpr>(previous_, false);
        }
        
        if (match(lexer::TokenType::KEYWORD_TRUE)) {
            return std::make_unique<LiteralExpr>(previous_, true);
        }
        
        // Handle string literals
        if (match(lexer::TokenType::CHAR_LITERAL)) {
            auto stringToken = previous_;
            return std::make_unique<LiteralExpr>(
                stringToken,
                std::string(stringToken.stringValue())
            );
        }
        
        if (match(lexer::TokenType::INTEGER_LITERAL)) {
            return std::make_unique<LiteralExpr>(
                previous_,
                previous_.intValue()
            );
        }
        
        if (match(lexer::TokenType::FLOAT_LITERAL)) {
            return std::make_unique<LiteralExpr>(
                previous_,
                previous_.floatValue()
            );
        }
        
        // Handle identifiers
        if (match(lexer::TokenType::IDENTIFIER)) {
            auto identifier = previous_;
            
            // Check for object instantiation with braces
            if (match(lexer::TokenType::LEFT_BRACE)) {
                consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after '{'");
                return std::make_unique<CallExpr>(
                    std::make_unique<VariableExpr>(identifier),
                    previous_,
                    std::vector<std::unique_ptr<Expr>>{},
                    makeRange(identifier, previous_)
                );
            }
            
            // Just a simple identifier
            return std::make_unique<VariableExpr>(identifier);
        }

        // Handle keywords that can be used as identifiers
        if (match({
                lexer::TokenType::KEYWORD_XOR,
                lexer::TokenType::KEYWORD_AND,
                lexer::TokenType::KEYWORD_OR
            })) {
            return std::make_unique<VariableExpr>(previous_);
        }
        
        if (match(lexer::TokenType::KEYWORD_OP)) {
            return parseOpExpr();
        }
        
        // Parenthesized expressions
        if (match(lexer::TokenType::LEFT_PAREN)) {
            auto leftParen = previous_;
            auto expr = expression();
            if (!expr) {
                error("Expected expression after '('");
                return nullptr;
            }
            
            auto closeParen = consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after expression");
            
            return std::make_unique<GroupExpr>(
                std::move(expr),
                makeRange(leftParen, closeParen)
            );
        }

        // Array literals [a, b, c]
        if (match(lexer::TokenType::LEFT_BRACKET)) {
            return parseArrayLiteral();
        }
        
        // Dictionary literals {key: value}
        if (match(lexer::TokenType::LEFT_BRACE)) {
            return parseDictionaryLiteral();
        }

        // Special expressions
        if (match(lexer::TokenType::KEYWORD_SIZEOF)) {
            return parseSizeOfExpr();
        }
        
        if (match(lexer::TokenType::KEYWORD_TYPEOF)) {
            return parseTypeOfExpr();
        }
        
        // Address specifier expressions
        if (match(lexer::TokenType::KEYWORD_ADDRESS)) {
            return parseAddressOfExpr();
        }
        
        // No valid primary expression found
        error("Expected expression");
        return nullptr;
    } catch (const std::exception& e) {
        error("Error parsing primary expression: " + std::string(e.what()));
        return nullptr;
    }
}

// Finish parsing a call expression
std::unique_ptr<Expr> Parser::finishCall(std::unique_ptr<Expr> callee) {
    std::vector<std::unique_ptr<Expr>> arguments;
    
    // Check if there are any arguments
    if (!check(lexer::TokenType::RIGHT_PAREN)) {
        do {
            // Limit number of arguments to prevent excessive recursion
            if (arguments.size() >= 255) {
                error("Cannot have more than 255 arguments.");
            }
            auto arg = expression();
            if (arg) {
                arguments.push_back(std::move(arg));
            }
        } while (match(lexer::TokenType::COMMA));
    }
    
    // Consume the closing parenthesis
    auto paren = consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after arguments");
    
    // Create and return the call expression
    return std::make_unique<CallExpr>(
        std::move(callee),
        paren,
        std::move(arguments),
        makeRange(previous_, paren)
    );
}

// Parse a qualified identifier like Flux.Integer
std::unique_ptr<Expr> Parser::qualifiedIdentifier() {
    auto start = current_;
    auto firstIdent = consume(lexer::TokenType::IDENTIFIER, "Expected identifier");
    
    // Create initial variable expression as a unique_ptr<Expr>
    std::unique_ptr<Expr> expr = std::make_unique<VariableExpr>(firstIdent);
    
    // Process each dot-separated part
    while (match(lexer::TokenType::DOT)) {
        auto name = consume(lexer::TokenType::IDENTIFIER, "Expected identifier after '.'");
        
        // Create a new GetExpr that holds the previous expression
        expr = std::make_unique<GetExpr>(
            std::move(expr), // Move the previous expression as the object
            name,
            makeRange(start, name)
        );
    }
    
    return expr;
}

// Parse a sizeof expression (sizeof(type))
std::unique_ptr<Expr> Parser::parseSizeOfExpr() {
    auto start = previous_;  // 'sizeof' keyword
    
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'sizeof'");
    
    // Parse the type
    auto targetType = type();
    if (!targetType) {
        error("Expected type in sizeof expression");
        return nullptr;
    }
    
    auto end = consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after type in sizeof");
    
    return std::make_unique<SizeOfExpr>(
        std::move(targetType),
        makeRange(start, end)
    );
}

// Parse a typeof expression (typeof(expr))
std::unique_ptr<Expr> Parser::parseTypeOfExpr() {
    auto start = previous_;  // 'typeof' keyword
    
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'typeof'");
    
    // Parse the expression
    auto expr = expression();
    if (!expr) {
        error("Expected expression in typeof");
        return nullptr;
    }
    
    auto end = consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after expression in typeof");
    
    return std::make_unique<TypeOfExpr>(
        std::move(expr),
        makeRange(start, end)
    );
}

// Parse an op expression (op<expr operator expr>)
std::unique_ptr<Expr> Parser::parseOpExpr() {
    auto start = previous_;  // 'op' keyword
    
    // Consume the opening angle bracket
    consume(lexer::TokenType::LESS, "Expected '<' after 'op'");
    
    // Parse the left operand - could be another op expression or a simple expression
    std::unique_ptr<Expr> left;
    
    // Check if left operand is another op expression
    if (match(lexer::TokenType::KEYWORD_OP)) {
        left = parseOpExpr(); // Recursively parse nested op expression
    } 
    // Handle integer, float, or identifier operands
    else if (check(lexer::TokenType::INTEGER_LITERAL) || 
             check(lexer::TokenType::FLOAT_LITERAL) ||
             check(lexer::TokenType::IDENTIFIER)) {
        
        if (check(lexer::TokenType::INTEGER_LITERAL)) {
            auto intToken = current_;
            advance(); // Consume the integer
            left = std::make_unique<LiteralExpr>(intToken, intToken.intValue());
        } else if (check(lexer::TokenType::FLOAT_LITERAL)) {
            auto floatToken = current_;
            advance(); // Consume the float
            left = std::make_unique<LiteralExpr>(floatToken, floatToken.floatValue());
        } else {
            auto identToken = current_;
            advance(); // Consume the identifier
            left = std::make_unique<VariableExpr>(identToken);
        }
    } 
    // Otherwise, try to parse any valid expression
    else {
        left = expression();
    }
    
    if (!left) {
        error("Expected expression for left operand of op");
        // Create a dummy expression to allow parsing to continue
        auto dummyToken = lexer::Token(lexer::TokenType::INTEGER_LITERAL, "0", 
                                      start.start(), start.end());
        left = std::make_unique<LiteralExpr>(dummyToken, static_cast<int64_t>(0));
    }
    
    // Parse the operator name (which can be an identifier or a custom operator symbol)
    std::string_view opName;
    if (check(lexer::TokenType::IDENTIFIER)) {
        opName = current_.lexeme();
        advance(); // Consume the identifier
    } 
    // Also allow for certain symbols as operator names
    else if (checkAny({lexer::TokenType::PLUS_PLUS,
                       lexer::TokenType::MINUS_MINUS,
                       lexer::TokenType::DOUBLE_ASTERISK,
                       lexer::TokenType::LESS_LESS,
                       lexer::TokenType::GREATER_GREATER})) {
        opName = current_.lexeme();
        advance(); // Consume the operator symbol
    }
    else {
        error("Expected identifier or operator symbol as operator name in op expression");
        opName = "error"; // Default operator name for error recovery
    }
    
    // Parse the right operand - similar to left operand
    std::unique_ptr<Expr> right;
    
    // Check if right operand is another op expression
    if (match(lexer::TokenType::KEYWORD_OP)) {
        right = parseOpExpr(); // Recursively parse nested op expression
    }
    // Handle integer, float, or identifier operands
    else if (check(lexer::TokenType::INTEGER_LITERAL) || 
             check(lexer::TokenType::FLOAT_LITERAL) ||
             check(lexer::TokenType::IDENTIFIER)) {
        
        if (check(lexer::TokenType::INTEGER_LITERAL)) {
            auto intToken = current_;
            advance(); // Consume the integer
            right = std::make_unique<LiteralExpr>(intToken, intToken.intValue());
        } else if (check(lexer::TokenType::FLOAT_LITERAL)) {
            auto floatToken = current_;
            advance(); // Consume the float
            right = std::make_unique<LiteralExpr>(floatToken, floatToken.floatValue());
        } else {
            auto identToken = current_;
            advance(); // Consume the identifier
            right = std::make_unique<VariableExpr>(identToken);
        }
    } 
    // Otherwise, try to parse any valid expression
    else {
        right = expression();
    }
    
    if (!right) {
        error("Expected expression for right operand of op");
        // Create a dummy expression to allow parsing to continue
        auto dummyToken = lexer::Token(lexer::TokenType::INTEGER_LITERAL, "0", 
                                      previous_.start(), previous_.end());
        right = std::make_unique<LiteralExpr>(dummyToken, static_cast<int64_t>(0));
    }
    
    // Consume the closing angle bracket
    auto end = consume(lexer::TokenType::GREATER, "Expected '>' after op expression");
    
    // Create and return the operator expression
    return std::make_unique<OpExpr>(
        std::move(left),
        opName,
        std::move(right),
        makeRange(start, end)
    );
}

// Parse an array literal [a, b, c]
std::unique_ptr<Expr> Parser::parseArrayLiteral() {
    auto start = previous_;  // '['
    std::vector<std::unique_ptr<Expr>> elements;
    
    // Parse array elements
    if (!check(lexer::TokenType::RIGHT_BRACKET)) {
        do {
            auto element = expression();
            if (element) {
                elements.push_back(std::move(element));
            } else {
                error("Expected expression in array literal");
            }
        } while (match(lexer::TokenType::COMMA));
    }
    
    auto end = consume(lexer::TokenType::RIGHT_BRACKET, "Expected ']' after array elements");
    
    return std::make_unique<ArrayExpr>(
        std::move(elements),
        makeRange(start, end)
    );
}

// Parse a dictionary literal {key: value, ...}
std::unique_ptr<Expr> Parser::parseDictionaryLiteral() {
    auto start = previous_;  // '{'
    
    // For now, we'll parse this as a simple block expression
    // In a full implementation, you might want a dedicated DictionaryExpr AST node
    std::vector<std::unique_ptr<Expr>> elements;
    
    // Parse dictionary entries
    if (!check(lexer::TokenType::RIGHT_BRACE)) {
        do {
            // Parse key
            auto key = expression();
            if (!key) {
                error("Expected key expression in dictionary literal");
                break;
            }
            
            // Expect colon
            if (!match(lexer::TokenType::COLON)) {
                error("Expected ':' after dictionary key");
                break;
            }
            
            // Parse value
            auto value = expression();
            if (!value) {
                error("Expected value expression in dictionary literal");
                break;
            }
            
            // For now, create a binary expression to represent key:value pair
            elements.push_back(std::make_unique<BinaryExpr>(
                std::move(key),
                lexer::Token(lexer::TokenType::COLON, ":", previous_.start(), previous_.end()),
                std::move(value),
                makeRange(previous_, previous_)
            ));
            
        } while (match(lexer::TokenType::COMMA));
    }
    
    auto end = consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after dictionary elements");
    
    return std::make_unique<ArrayExpr>(
        std::move(elements),
        makeRange(start, end)
    );
}

// Parse an address-of expression
std::unique_ptr<Expr> Parser::parseAddressOfExpr() {
    return parseAddressSpecifier();
}

// Parse a type expression
std::unique_ptr<TypeExpr> Parser::type() {
    // Save initial position for error recovery
    lexer::Token startToken = current_;
    
    // Handle type modifiers first
    bool isVolatile = match(lexer::TokenType::KEYWORD_VOLATILE);
    bool isConst = match(lexer::TokenType::KEYWORD_CONST);
    
    // 1. Handle keywords that define types
    if (match({lexer::TokenType::KEYWORD_CLASS, 
              lexer::TokenType::KEYWORD_OBJECT, 
              lexer::TokenType::KEYWORD_STRUCT,
              lexer::TokenType::KEYWORD_DATA,
              lexer::TokenType::KEYWORD_SIGNED,
              lexer::TokenType::KEYWORD_UNSIGNED})) {
        
        // Convert keyword to string type name
        std::string_view typeName;
        switch (previous_.type()) {
            case lexer::TokenType::KEYWORD_CLASS:  typeName = "class"; break;
            case lexer::TokenType::KEYWORD_OBJECT: typeName = "object"; break;
            case lexer::TokenType::KEYWORD_STRUCT: typeName = "struct"; break;
            case lexer::TokenType::KEYWORD_DATA: return dataType();
            case lexer::TokenType::KEYWORD_SIGNED: return dataType();
            case lexer::TokenType::KEYWORD_UNSIGNED: return dataType();
            default: /* Unreachable */ break;
        }
        
        // Create base type
        auto baseType = std::make_unique<NamedTypeExpr>(typeName, makeRange(previous_));
        
        // Check for pointer modifier
        if (match(lexer::TokenType::ASTERISK)) {
            return std::make_unique<PointerTypeExpr>(
                std::move(baseType),
                makeRange(previous_, previous_),
                isVolatile,
                isConst
            );
        }
        
        return baseType;
    }
    
    // 2. Handle pointers to types
    if (match(lexer::TokenType::ASTERISK)) {
        auto pointerToken = previous_;
        auto pointeeType = type();
        
        if (!pointeeType) {
            error("Expected type after '*'");
            return nullptr;
        }
        
        return std::make_unique<PointerTypeExpr>(
            std::move(pointeeType),
            makeRange(pointerToken, previous_),
            isVolatile,
            isConst
        );
    }
    
    // 3. Handle function types
    if (match(lexer::TokenType::KEYWORD_DEF)) {
        return functionType();
    }
    
    // 4. Handle void type
    if (match(lexer::TokenType::KEYWORD_VOID)) {
        return std::make_unique<NamedTypeExpr>("void", makeRange(previous_));
    }
    
    // 5. Handle named and qualified types
    if (check(lexer::TokenType::IDENTIFIER)) {
        auto identType = qualifiedType();
        
        // Check for array modifier
        if (match(lexer::TokenType::LEFT_BRACKET)) {
            return arrayType(std::move(identType));
        }
        
        return identType;
    }
    
    // If we get here, we couldn't parse a valid type
    error("Expected type");
    return nullptr;
}

// Helper to check if a token is a type modifier
bool Parser::isTypeModifier(const lexer::Token& token) const {
    return token.isOneOf({
        lexer::TokenType::KEYWORD_CONST,
        lexer::TokenType::KEYWORD_VOLATILE,
        lexer::TokenType::KEYWORD_SIGNED,
        lexer::TokenType::KEYWORD_UNSIGNED,
        lexer::TokenType::KEYWORD_PACKED
    });
}

// Parse a qualified type like Flux.Integer
std::unique_ptr<TypeExpr> Parser::qualifiedType() {
    auto start = current_;
    
    // Parse the first part of the qualified name
    auto firstIdent = consume(lexer::TokenType::IDENTIFIER, "Expected type name");
    std::vector<std::string_view> parts;
    parts.push_back(firstIdent.lexeme());
    
    // Process each dot-separated part
    while (match(lexer::TokenType::DOT)) {
        auto name = consume(lexer::TokenType::IDENTIFIER, "Expected identifier after '.'");
        parts.push_back(name.lexeme());
    }
    
    // Combine the parts into a single qualified name
    std::string qualified_name;
    for (size_t i = 0; i < parts.size(); ++i) {
        qualified_name += parts[i];
        if (i < parts.size() - 1) {
            qualified_name += ".";
        }
    }
    
    // Create a named type with the combined qualified name
    return std::make_unique<NamedTypeExpr>(
        qualified_name,
        makeRange(start, previous_)
    );
}

// Parse a pointer type
std::unique_ptr<TypeExpr> Parser::pointerType(std::unique_ptr<TypeExpr> pointeeType) {
    // Create a pointer type with the given pointee type
    auto range = makeRange(pointeeType->range.start, previous_.end());
    return std::make_unique<PointerTypeExpr>(
        std::move(pointeeType),
        range,
        false, // Not volatile by default
        false  // Not const by default
    );
}

// Parse a named type
std::unique_ptr<TypeExpr> Parser::namedType() {
    auto name = consume(lexer::TokenType::IDENTIFIER, "Expected type name");
    
    return std::make_unique<NamedTypeExpr>(
        name.lexeme(),
        makeRange(name)
    );
}

// Parse an array type
std::unique_ptr<TypeExpr> Parser::arrayType(std::unique_ptr<TypeExpr> elementType) {
    // Parse array size expression (optional)
    std::unique_ptr<Expr> sizeExpr;
    if (!check(lexer::TokenType::RIGHT_BRACKET)) {
        sizeExpr = expression();
    }
    
    auto end = consume(lexer::TokenType::RIGHT_BRACKET, "Expected ']' after array type");
    
    return std::make_unique<ArrayTypeExpr>(
        std::move(elementType),
        std::move(sizeExpr), // This might be nullptr for dynamic arrays
        makeRange(previous_, end)
    );
}

// Parse a function type
std::unique_ptr<TypeExpr> Parser::functionType() {
    // Parse parameter types
    consume(lexer::TokenType::LEFT_PAREN, "Expected '(' after 'def'");
    
    std::vector<std::unique_ptr<TypeExpr>> parameterTypes;
    
    if (!check(lexer::TokenType::RIGHT_PAREN)) {
        do {
            auto paramType = type();
            if (paramType) {
                parameterTypes.push_back(std::move(paramType));
            }
        } while (match(lexer::TokenType::COMMA));
    }
    
    consume(lexer::TokenType::RIGHT_PAREN, "Expected ')' after parameter types");
    
    // Parse return type
    consume(lexer::TokenType::ARROW, "Expected '->' after parameter types");
    
    auto returnType = type();
    if (!returnType) {
        error("Expected return type after '->'");
        returnType = std::make_unique<NamedTypeExpr>("void", makeRange(previous_));
    }
    
    return std::make_unique<FunctionTypeExpr>(
        std::move(parameterTypes),
        std::move(returnType),
        makeRange(previous_)
    );
}

// Parse a data type
std::unique_ptr<TypeExpr> Parser::dataType() {
    bool isSigned = !previous_.is(lexer::TokenType::KEYWORD_UNSIGNED);
    
    // Parse 'data' keyword if not already consumed
    if (!previous_.is(lexer::TokenType::KEYWORD_DATA)) {
        consume(lexer::TokenType::KEYWORD_DATA, "Expected 'data' keyword");
    }
    
    // Parse the bit size
    consume(lexer::TokenType::LEFT_BRACE, "Expected '{' after 'data'");
    
    // Parse the size expression
    auto sizeToken = consume(lexer::TokenType::INTEGER_LITERAL, "Expected bit size");
    int64_t bits = sizeToken.intValue();
    
    consume(lexer::TokenType::RIGHT_BRACE, "Expected '}' after bit size");
    
    // Parse alignment if present
    std::optional<size_t> alignment = parseAlignmentAttribute();
    
    // Check for volatile modifier
    bool isVolatile = match(lexer::TokenType::KEYWORD_VOLATILE);
    
    return std::make_unique<DataTypeExpr>(
        bits,
        isSigned,
        makeRange(previous_),
        alignment,
        isVolatile
    );
}

// Parse a delimited list of items
template<typename T>
std::vector<T> Parser::parseDelimitedList(
    lexer::TokenType delimiter,
    lexer::TokenType end,
    std::function<T()> parseItem) {
    
    std::vector<T> items;
    
    if (!check(end)) {
        do {
            items.push_back(parseItem());
        } while (match(delimiter));
    }
    
    consume(end, "Expected end of list");
    
    return items;
}

} // namespace parser
} // namespace flux