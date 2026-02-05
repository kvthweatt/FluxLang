// Standard Library Test Module
//
// Test: string objects
// Located at: src\stdlib\builtins\string_object_raw.fx
// Imported by: src\stdlib\runtime\redruntime.fx

#import "standard.fx";

def main()->int
{
    string s("Get ready to test strings!\0");

    print(s.val()); print();
    print(s.len()); print();
    print(s.set("Setting a new string.\0")); print();
    s.printval(); print();
    print(!s.equals("Not this!\0")); print();
    print(s.contains("new\0")); print();
    print(s.startswith("Setting\0")); print();
    print(s.endswith("string.\0")); print();
    //print(s.indexof("ready\0")); print();      // requires find_substring
    print(s.indexof_char('r')); print();
    //print(s.lastindexof_char('!')); print();   // requires find_last_char
    //print(s.count_occurances("t\0")); print(); // requires count_substring
    print(s.charat(5)); print();
    s.setat(s.len()-1,'!');
    s.printval(); print();
    print(s.substring(10,12)); print();
    print(s.count_words()); print();
    print(s.replace("string\0","stubid\0")); print();
    s.printval(); print();

	return 0;
};