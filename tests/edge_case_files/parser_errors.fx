// This file contains intentional syntax errors for testing

def main() -> int {
    // Missing semicolon
    return 0
}

def badFunction(int x, float y -> int {  // Missing closing parenthesis
    return x + y;
};

def anotherBad() -> int {
    if (true {  // Missing closing parenthesis
        return 1;
    };
    return 0;
