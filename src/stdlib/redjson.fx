// redjson.fx - JSON Parser Library
// Parse JSON strings into navigable structures

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_JSON
#def FLUX_STANDARD_JSON 1;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_STRINGS
#import "red_string_utilities.fx";
#endif;

        enum JSONType
        {
            JSON_NULL,
            JSON_BOOL,
            JSON_NUMBER,
            JSON_STRING,
            JSON_ARRAY,
            JSON_OBJECT
        };

namespace standard
{
    namespace json
    {
        // ============ JSON VALUE TYPES ============

        struct JSONArray;
        struct JSONValue;
        struct JSObjectPair;
        struct JSONObject;
        struct JSONParser;

        // ============ JSON ARRAY ============
        
        struct JSONArray
        {
            JSONValue* values;
            int count;
            int capacity;
        };

        // ============ JSON VALUE STRUCTURE ============
        
        struct JSONValue
        {
            JSONType type;
            
            // Union-like storage for different types
            bool bool_value;
            float number_value;
            byte* string_value;
            JSONArray* array_value;
            JSONObject* object_value;
        };
        
        // ============ JSON OBJECT ============
        
        struct JSONObjectPair
        {
            byte* key;
            JSONValue value;
        };
        
        struct JSONObject
        {
            JSONObjectPair* pairs;
            int count;
            int capacity;
        };
        
        // ============ PARSER STATE ============
        
        struct JSONParser
        {
            byte* input;
            int position;
            int length;
            byte* error_message;
        };

        // ============ HELPER FUNCTIONS ============
        
        // Skip whitespace
        def skip_whitespace(JSONParser* parser) -> void
        {
            while (parser.position < parser.length)
            {
                byte ch = parser.input[parser.position];
                if (ch == ' ' | ch == '\t' | ch == '\n' | ch == '\r')
                {
                    parser.position++;
                }
                else
                {
                    break;
                };
            };
        };
        
        // Peek current character
        def peek_char(JSONParser* parser) -> byte
        {
            if (parser.position >= parser.length)
            {
                return (byte)0;
            };
            return parser.input[parser.position];
        };
        
        // Consume and return current character
        def consume_char(JSONParser* parser) -> byte
        {
            if (parser.position >= parser.length)
            {
                return (byte)0;
            };
            byte ch = parser.input[parser.position];
            parser.position++;
            return ch;
        };
        
        // Check if character is digit
        def is_digit(byte ch) -> bool
        {
            return ch >= '0' & ch <= '9';
        };
        
        // ============ PARSE NULL ============
        
        def parse_null(JSONParser* parser, JSONValue* value) -> bool
        {
            // Expect "null"
            if (parser.position + 4 > parser.length)
            {
                parser.error_message = "Unexpected end while parsing null\0";
                return false;
            };
            
            if (parser.input[parser.position] == 'n' &
                parser.input[parser.position + 1] == 'u' &
                parser.input[parser.position + 2] == 'l' &
                parser.input[parser.position + 3] == 'l')
            {
                parser.position += 4;
                value.type = JSONType.JSON_NULL;
                return true;
            };
            
            parser.error_message = "Expected 'null'\0";
            return false;
        };
        
        // ============ PARSE BOOLEAN ============
        
        def parse_bool(JSONParser* parser, JSONValue* value) -> bool
        {
            // Try "true"
            if (parser.position + 4 <= parser.length)
            {
                if (parser.input[parser.position] == 't' &
                    parser.input[parser.position + 1] == 'r' &
                    parser.input[parser.position + 2] == 'u' &
                    parser.input[parser.position + 3] == 'e')
                {
                    parser.position += 4;
                    value.type = JSONType.JSON_BOOL;
                    value.bool_value = true;
                    return true;
                };
            };
            
            // Try "false"
            if (parser.position + 5 <= parser.length)
            {
                if (parser.input[parser.position] == 'f' &
                    parser.input[parser.position + 1] == 'a' &
                    parser.input[parser.position + 2] == 'l' &
                    parser.input[parser.position + 3] == 's' &
                    parser.input[parser.position + 4] == 'e')
                {
                    parser.position += 5;
                    value.type = JSONType.JSON_BOOL;
                    value.bool_value = false;
                    return true;
                };
            };
            
            parser.error_message = "Expected 'true' or 'false'\0";
            return false;
        };
        
        // ============ PARSE NUMBER ============
        
        def parse_number(JSONParser* parser, JSONValue* value) -> bool
        {
            int start = parser.position;
            bool is_negative = false;
            bool has_decimal = false;
            
            // Handle negative sign
            if (peek_char(parser) == '-')
            {
                is_negative = true;
                consume_char(parser);
            };
            
            // Parse integer part
            if (!is_digit(peek_char(parser)))
            {
                parser.error_message = "Expected digit in number\0";
                return false;
            };
            
            while (is_digit(peek_char(parser)))
            {
                consume_char(parser);
            };
            
            // Parse decimal part
            if (peek_char(parser) == '.')
            {
                has_decimal = true;
                consume_char(parser);
                
                if (!is_digit(peek_char(parser)))
                {
                    parser.error_message = "Expected digit after decimal point\0";
                    return false;
                };
                
                while (is_digit(peek_char(parser)))
                {
                    consume_char(parser);
                };
            };
            
            // Parse exponent (e/E)
            byte ch = peek_char(parser);
            if (ch == 'e' | ch == 'E')
            {
                consume_char(parser);
                
                byte sign_ch = peek_char(parser);
                if (sign_ch == '+' | sign_ch == '-')
                {
                    consume_char(parser);
                };
                
                if (!is_digit(peek_char(parser)))
                {
                    parser.error_message = "Expected digit in exponent\0";
                    return false;
                };
                
                while (is_digit(peek_char(parser)))
                {
                    consume_char(parser);
                };
            };
            
            // Convert string to number
            int end = parser.position;
            int num_len = end - start;
            
            // Simple number conversion (only handles basic floats for now)
            float result = 0.0;
            float decimal_place = 1.0;
            bool in_decimal = false;
            
            for (int i = start; i < end; i++)
            {
                byte digit = parser.input[i];
                
                if (digit == '-')
                {
                    continue;
                };
                
                if (digit == '.')
                {
                    in_decimal = true;
                    continue;
                };
                
                if (digit >= '0' & digit <= '9')
                {
                    int d = (int)(digit - '0');
                    
                    if (in_decimal)
                    {
                        decimal_place = decimal_place / 10.0;
                        result = result + ((float)d * decimal_place);
                    }
                    else
                    {
                        result = result * 10.0 + (float)d;
                    };
                };
            };
            
            if (is_negative)
            {
                result = -result;
            };
            
            value.type = JSONType.JSON_NUMBER;
            value.number_value = result;
            return true;
        };
        
        // ============ PARSE STRING ============
        
        def parse_string(JSONParser* parser, byte** out_string) -> bool
        {
            // Expect opening quote
            if (consume_char(parser) != '"')
            {
                parser.error_message = "Expected opening quote\0";
                return false;
            };
            
            int start = parser.position;
            int str_len = 0;
            
            // Find end of string and count length
            while (parser.position < parser.length)
            {
                byte ch = parser.input[parser.position];
                
                if (ch == '"')
                {
                    break;
                };
                
                if (ch == '\\')
                {
                    // Skip escape sequence
                    parser.position++;
                    if (parser.position >= parser.length)
                    {
                        parser.error_message = "Unterminated escape sequence\0";
                        return false;
                    };
                };
                
                parser.position++;
                str_len++;
            };
            
            if (parser.position >= parser.length)
            {
                parser.error_message = "Unterminated string\0";
                return false;
            };
            
            // Allocate string
            byte* str = malloc((u64)(str_len + 1));
            if (str == (byte*)0)
            {
                parser.error_message = "Memory allocation failed\0";
                return false;
            };
            
            // Copy string with escape handling
            int write_pos = 0;
            parser.position = start;
            
            while (parser.position < parser.length)
            {
                byte ch = parser.input[parser.position];
                
                if (ch == '"')
                {
                    break;
                };
                
                if (ch == '\\')
                {
                    parser.position++;
                    byte escaped = parser.input[parser.position];
                    
                    if (escaped == 'n')
                    {
                        str[write_pos] = '\n';
                    }
                    elif (escaped == 't')
                    {
                        str[write_pos] = '\t';
                    }
                    elif (escaped == 'r')
                    {
                        str[write_pos] = '\r';
                    }
                    elif (escaped == '\\')
                    {
                        str[write_pos] = '\\';
                    }
                    elif (escaped == '"')
                    {
                        str[write_pos] = '"';
                    }
                    elif (escaped == '/')
                    {
                        str[write_pos] = '/';
                    }
                    else
                    {
                        str[write_pos] = escaped;
                    };
                }
                else
                {
                    str[write_pos] = ch;
                };
                
                parser.position++;
                write_pos++;
            };
            
            str[write_pos] = (byte)0;
            
            // Consume closing quote
            if (consume_char(parser) != '"')
            {
                free(str);
                parser.error_message = "Expected closing quote\0";
                return false;
            };
            
            *out_string = str;
            return true;
        };
        
        // Forward declaration for recursive parsing
        def parse_value(JSONParser* parser, JSONValue* value) -> bool;
        
        // ============ PARSE ARRAY ============
        
        def parse_array(JSONParser* parser, JSONValue* value) -> bool
        {
            // Expect opening bracket
            if (consume_char(parser) != '[')
            {
                parser.error_message = "Expected '['\0";
                return false;
            };
            
            // Allocate array
            JSONArray* array = malloc((u64)sizeof(JSONArray));
            if (array == (JSONArray*)0)
            {
                parser.error_message = "Memory allocation failed\0";
                return false;
            };
            
            array.capacity = 16;
            array.count = 0;
            array.values = malloc((u64)(sizeof(JSONValue) * array.capacity));
            
            if (array.values == (JSONValue*)0)
            {
                free(array);
                parser.error_message = "Memory allocation failed\0";
                return false;
            };
            
            skip_whitespace(parser);
            
            // Check for empty array
            if (peek_char(parser) == ']')
            {
                consume_char(parser);
                value.type = JSONType.JSON_ARRAY;
                value.array_value = array;
                return true;
            };
            
            // Parse array elements
            while (true)
            {
                skip_whitespace(parser);
                
                // Expand capacity if needed
                if (array.count >= array.capacity)
                {
                    int new_capacity = array.capacity * 2;
                    JSONValue* new_values = malloc((u64)(sizeof(JSONValue) * new_capacity));
                    
                    if (new_values == (JSONValue*)0)
                    {
                        parser.error_message = "Memory allocation failed\0";
                        return false;
                    };
                    
                    // Copy old values
                    for (int i = 0; i < array.count; i++)
                    {
                        new_values[i] = array.values[i];
                    };
                    
                    free(array.values);
                    array.values = new_values;
                    array.capacity = new_capacity;
                };
                
                // Parse value
                if (!parse_value(parser, @array.values[array.count]))
                {
                    return false;
                };
                
                array.count++;
                
                skip_whitespace(parser);
                
                byte next = peek_char(parser);
                if (next == ']')
                {
                    consume_char(parser);
                    break;
                }
                elif (next == ',')
                {
                    consume_char(parser);
                    continue;
                }
                else
                {
                    parser.error_message = "Expected ',' or ']' in array\0";
                    return false;
                };
            };
            
            value.type = JSONType.JSON_ARRAY;
            value.array_value = array;
            return true;
        };
        
        // ============ PARSE OBJECT ============
        
        def parse_object(JSONParser* parser, JSONValue* value) -> bool
        {
            // Expect opening brace
            if (consume_char(parser) != '{')
            {
                parser.error_message = "Expected '{'\0";
                return false;
            };
            
            // Allocate object
            JSONObject* ox = malloc((u64)sizeof(JSONObject));
            if (ox == (JSONObject*)0)
            {
                parser.error_message = "Memory allocation failed\0";
                return false;
            };
            
            ox.capacity = 16;
            ox.count = 0;
            ox.pairs = malloc((u64)(sizeof(JSONObjectPair) * ox.capacity));
            
            if (ox.pairs == (JSONObjectPair*)0)
            {
                free(ox);
                parser.error_message = "Memory allocation failed\0";
                return false;
            };
            
            skip_whitespace(parser);
            
            // Check for empty object
            if (peek_char(parser) == '}')
            {
                consume_char(parser);
                value.type = JSON_OBJECT;
                value.object_value = ox;
                return true;
            };
            
            // Parse object pairs
            while (true)
            {
                skip_whitespace(parser);
                
                // Expand capacity if needed
                if (ox.count >= ox.capacity)
                {
                    int new_capacity = ox.capacity * 2;
                    JSONObjectPair* new_pairs = malloc((u64)(sizeof(JSONObjectPair) * new_capacity));
                    
                    if (new_pairs == (JSONObjectPair*)0)
                    {
                        parser.error_message = "Memory allocation failed\0";
                        return false;
                    };
                    
                    // Copy old pairs
                    for (int i = 0; i < ox.count; i++)
                    {
                        new_pairs[i] = ox.pairs[i];
                    };
                    
                    free(ox.pairs);
                    ox.pairs = new_pairs;
                    ox.capacity = new_capacity;
                };
                
                // Parse key (must be string)
                byte* key = (byte*)0;
                if (!parse_string(parser, @key))
                {
                    return false;
                };
                
                skip_whitespace(parser);
                
                // Expect colon
                if (consume_char(parser) != ':')
                {
                    free(key);
                    parser.error_message = "Expected ':' after object key\0";
                    return false;
                };
                
                skip_whitespace(parser);
                
                // Parse value
                ox.pairs[ox.count].key = key;
                if (!parse_value(parser, @ox.pairs[ox.count].value))
                {
                    return false;
                };
                
                ox.count++;
                
                skip_whitespace(parser);
                
                byte next = peek_char(parser);
                if (next == '}')
                {
                    consume_char(parser);
                    break;
                }
                elif (next == ',')
                {
                    consume_char(parser);
                    continue;
                }
                else
                {
                    parser.error_message = "Expected ',' or '}' in object\0";
                    return false;
                };
            };
            
            value.type = JSONType.JSON_OBJECT;
            value.object_value = ox;
            return true;
        };
        
        // ============ PARSE VALUE (MAIN) ============
        
        def parse_value(JSONParser* parser, JSONValue* value) -> bool
        {
            skip_whitespace(parser);
            
            byte ch = peek_char(parser);
            
            if (ch == 'n')
            {
                return parse_null(parser, value);
            }
            elif (ch == 't' | ch == 'f')
            {
                return parse_bool(parser, value);
            }
            elif (ch == '"')
            {
                byte* str = (byte*)0;
                if (!parse_string(parser, @str))
                {
                    return false;
                };
                value.type = JSONType.JSON_STRING;
                value.string_value = str;
                return true;
            }
            elif (ch == '[')
            {
                return parse_array(parser, value);
            }
            elif (ch == '{')
            {
                return parse_object(parser, value);
            }
            elif (ch == '-' | is_digit(ch))
            {
                return parse_number(parser, value);
            }
            else
            {
                parser.error_message = "Unexpected character\0";
                return false;
            };
        };
        
        // ============ PUBLIC API ============
        
        // Parse JSON string
        def json_parse(byte* input, JSONValue* value) -> bool
        {
            JSONParser parser;
            parser.input = input;
            parser.position = 0;
            parser.error_message = (byte*)0;
            
            // Calculate length
            parser.length = 0;
            while (input[parser.length] != (byte)0)
            {
                parser.length++;
            };
            
            return parse_value(@parser, value);
        };
        
        // Get object value by key
        def json_object_get(JSONObject* ox, byte* key) -> JSONValue*
        {
            for (int i = 0; i < ox.count; i++)
            {
                // Compare keys
                byte* obj_key = ox.pairs[i].key;
                int j = 0;
                bool match = true;
                
                while (true)
                {
                    if (obj_key[j] != key[j])
                    {
                        match = false;
                        break;
                    };
                    
                    if (obj_key[j] == (byte)0)
                    {
                        break;
                    };
                    
                    j++;
                };
                
                if (match)
                {
                    return @ox.pairs[i].value;
                };
            };
            
            return (JSONValue*)0;
        };
        
        // Get array element by index
        def json_array_get(JSONArray* array, int index) -> JSONValue*
        {
            if (index < 0 | index >= array.count)
            {
                return (JSONValue*)0;
            };
            
            return @array.values[index];
        };
        
        // Free JSON value (recursive)
        def json_free(JSONValue* value) -> void
        {
            if (value.type == JSON_STRING)
            {
                if (value.string_value != (byte*)0)
                {
                    free(value.string_value);
                };
            }
            elif (value.type == JSON_ARRAY)
            {
                if (value.array_value != (JSONArray*)0)
                {
                    for (int i = 0; i < value.array_value.count; i++)
                    {
                        json_free(@value.array_value.values[i]);
                    };
                    free(value.array_value.values);
                    free(value.array_value);
                };
            }
            elif (value.type == JSON_OBJECT)
            {
                if (value.object_value != (JSONObject*)0)
                {
                    for (int i = 0; i < value.object_value.count; i++)
                    {
                        free(value.object_value.pairs[i].key);
                        json_free(@value.object_value.pairs[i].value);
                    };
                    free(value.object_value.pairs);
                    free(value.object_value);
                };
            };
        };
    };
};

using standard::json;

#endif;
