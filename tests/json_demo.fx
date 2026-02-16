#import "redstandard.fx";
#import "redformat.fx";
#import "redjson.fx";

using standard::format;
using standard::format::colors;
using standard::json;



def print_indent(int level) -> void
{
    for (int i = 0; i < level; i++)
    {
        print("  \0");
    };
};

def print_json_value(JSONValue* value, int indent) -> void
{
    if (value.type == JSON_NULL)
    {
        print_cyan("null\0");
    }
    elif (value.type == JSON_BOOL)
    {
        if (value.bool_value)
        {
            print_green("true\0");
        }
        else
        {
            print_red("false\0");
        };
    }
    elif (value.type == JSON_NUMBER)
    {
        print_yellow("\0");
        print(value.number_value, 2);
        print(colors::RESET);
    }
    elif (value.type == JSON_STRING)
    {
        print("\"\0");
        print(value.string_value);
        print("\"\0");
    }
    elif (value.type == JSON_ARRAY)
    {
        print("[\n\0");
        
        for (int i = 0; i < value.array_value.count; i++)
        {
            print_indent(indent + 1);
            print_json_value(@value.array_value.values[i], indent + 1);
            
            if (i < value.array_value.count - 1)
            {
                print(",\0");
            };
            print("\n\0");
        };
        
        print_indent(indent);
        print("]\0");
    }
    elif (value.type == JSON_OBJECT)
    {
        print("{\n\0");
        
        for (int i = 0; i < value.object_value.count; i++)
        {
            print_indent(indent + 1);
            print_magenta("\"\0");
            print(value.object_value.pairs[i].key);
            print_magenta("\"\0");
            print(": \0");
            print_json_value(@value.object_value.pairs[i].value, indent + 1);
            
            if (i < value.object_value.count - 1)
            {
                print(",\0");
            };
            print("\n\0");
        };
        
        print_indent(indent);
        print("}\0");
    };
};

def main() -> int
{
    print("\n\0");
    print_banner_colored("JSON PARSER DEMO", 70, colors::BRIGHT_CYAN);
    print("\n\0");
    
    // ============ DEMO 1: Simple Values ============
    print_banner("SIMPLE VALUES", 70);
    print("\n\0");
    
    JSONValue value;
    
    print("Parsing null:\n  \0");
    json_parse("null\0", @value);
    print_json_value(@value, 0);
    print("\n\n\0");
    
    print("Parsing boolean true:\n  \0");
    json_parse("true\0", @value);
    print_json_value(@value, 0);
    print("\n\n\0");
    
    print("Parsing boolean false:\n  \0");
    json_parse("false\0", @value);
    print_json_value(@value, 0);
    print("\n\n\0");
    
    print("Parsing number 42:\n  \0");
    json_parse("42\0", @value);
    print_json_value(@value, 0);
    print("\n\n\0");
    
    print("Parsing number -3.14:\n  \0");
    json_parse("-3.14\0", @value);
    print_json_value(@value, 0);
    print("\n\n\0");
    
    print("Parsing string:\n  \0");
    json_parse("\"Hello, JSON!\"\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    // ============ DEMO 2: Arrays ============
    print_banner("ARRAYS", 70);
    print("\n\0");
    
    print("Empty array:\n\0");
    json_parse("[]\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    print("Number array:\n\0");
    json_parse("[1, 2, 3, 4, 5]\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    print("Mixed type array:\n\0");
    json_parse("[42, \"hello\", true, null, 3.14]\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    print("Nested array:\n\0");
    json_parse("[[1, 2], [3, 4], [5, 6]]\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    // ============ DEMO 3: Objects ============
    print_banner("OBJECTS", 70);
    print("\n\0");
    
    print("Empty object:\n\0");
    json_parse("{}\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    print("Simple object:\n\0");
    json_parse("{\"name\": \"Alice\", \"age\": 30}\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    print("Object with different types:\n\0");
    json_parse("{\"active\": true, \"count\": 42, \"label\": \"test\"}\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    // ============ DEMO 4: Nested Structures ============
    print_banner("NESTED STRUCTURES", 70);
    print("\n\0");
    
    print("Object with nested array:\n\0");
    json_parse("{\"numbers\": [1, 2, 3], \"name\": \"test\"}\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    print("Array of objects:\n\0");
    json_parse("[{\"x\": 1, \"y\": 2}, {\"x\": 3, \"y\": 4}]\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    print("Nested objects:\n\0");
    json_parse("{\"user\": {\"name\": \"Bob\", \"age\": 25}, \"active\": true}\0", @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    // ============ DEMO 5: Complex JSON ============
    print_banner("COMPLEX JSON DOCUMENT", 70);
    print("\n\0");
    
    byte[] complex_json = "{\
  \"version\": 1.0,\
  \"users\": [\
    {\"id\": 1, \"name\": \"Alice\", \"admin\": true},\
    {\"id\": 2, \"name\": \"Bob\", \"admin\": false},\
    {\"id\": 3, \"name\": \"Charlie\", \"admin\": false}\
  ],\
  \"settings\": {\
    \"theme\": \"dark\",\
    \"notifications\": true,\
    \"maxItems\": 100\
  }\
}\0";
    
    json_parse(complex_json, @value);
    print_json_value(@value, 0);
    print("\n\n\0");
    
    // ============ DEMO 6: Navigation ============
    print_banner("NAVIGATING JSON DATA", 70);
    print("\n\0");
    
    print("Accessing object fields:\n\0");
    
    JSONValue* version = json_object_get(value.object_value, "version\0");
    if (version != (JSONValue*)0)
    {
        print("  version = \0");
        print(version.number_value, 1);
        print("\n\0");
    };
    
    JSONValue* users = json_object_get(value.object_value, "users\0");
    if (users != (JSONValue*)0 & users.type == JSON_ARRAY)
    {
        print("  Found users array with \0");
        print(users.array_value.count);
        print(" elements\n\0");
        
        // Get first user
        JSONValue* first_user = json_array_get(users.array_value, 0);
        if (first_user != (JSONValue*)0 & first_user.type == JSON_OBJECT)
        {
            print("  First user:\n\0");
            
            JSONValue* name = json_object_get(first_user.object_value, "name\0");
            if (name != (JSONValue*)0)
            {
                print("    name = \"\0");
                print(name.string_value);
                print("\"\n\0");
            };
            
            JSONValue* admin = json_object_get(first_user.object_value, "admin\0");
            if (admin != (JSONValue*)0)
            {
                print("    admin = \0");
                if (admin.bool_value)
                {
                    print("true\0");
                }
                else
                {
                    print("false\0");
                };
                print("\n\0");
            };
        };
    };
    
    JSONValue* settings = json_object_get(value.object_value, "settings\0");
    if (settings != (JSONValue*)0 & settings.type == JSON_OBJECT)
    {
        print("  Settings:\n\0");
        
        JSONValue* theme = json_object_get(settings.object_value, "theme\0");
        if (theme != (JSONValue*)0)
        {
            print("    theme = \"\0");
            print(theme.string_value);
            print("\"\n\0");
        };
        
        JSONValue* max_items = json_object_get(settings.object_value, "maxItems\0");
        if (max_items != (JSONValue*)0)
        {
            print("    maxItems = \0");
            print((int)max_items.number_value);
            print("\n\0");
        };
    };
    
    json_free(@value);
    print("\n\0");
    
    // ============ DEMO 7: Whitespace Handling ============
    print_banner("WHITESPACE HANDLING", 70);
    print("\n\0");
    
    print("JSON with lots of whitespace:\n\0");
    byte[] spaced_json = "  {\
    \"compact\"  :   false  ,  \
    \"value\"    :   42     \
  }  \0";
    
    json_parse(spaced_json, @value);
    print_json_value(@value, 0);
    json_free(@value);
    print("\n\n\0");
    
    // ============ END ============
    hline_heavy(70);
    print_centered("End of JSON Parser Demo", 70);
    hline_heavy(70);
    print("\n\0");
    
    return 0;
};
