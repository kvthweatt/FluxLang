// Author: Karac V. Thweatt

// json_test.fx - Tests for json.fx

#import "standard.fx";
#import "json.fx";

using standard::io::console,
      json;

global int g_pass, g_fail;

def pass(byte* name) -> void
{
	print("[PASS] \0");
	print(name);
	print("\n\0");
	g_pass = g_pass + 1;
	return;
};

def fail(byte* name) -> void
{
	print("[FAIL] \0");
	print(name);
	print("\n\0");
	g_fail = g_fail + 1;
	return;
};

def check(bool ok, byte* name) -> void
{
	if (ok) { pass(name); }
	else    { fail(name); };
	return;
};

def test_null() -> void
{
	JSONNode n();
	check(n.is_null(),  "null: default type is null\0");
	n.set_bool(true);
	n.set_null();
	check(n.is_null(),  "null: set_null clears type\0");
	n.__exit();
	return;
};

def test_bool() -> void
{
	JSONNode n();
	n.set_bool(true);
	check(n.is_bool(),  "bool: is_bool\0");
	check(n.as_bool(),  "bool: as_bool true\0");
	n.set_bool(false);
	check(!n.as_bool(), "bool: as_bool false\0");
	n.__exit();
	return;
};

def test_int() -> void
{
	JSONNode n();
	n.set_int((i64)42);
	check(n.is_int(),          "int: is_int\0");
	check(n.as_int() == 42,    "int: as_int 42\0");
	n.set_int((i64)-7);
	check(n.as_int() == -7,    "int: as_int -7\0");
	n.__exit();
	return;
};

def test_float() -> void
{
	JSONNode n();
	n.set_float(3.14);
	check(n.is_float(),        "float: is_float\0");
	check(n.as_float() > 3.0,  "float: as_float > 3.0\0");
	check(n.as_float() < 4.0,  "float: as_float < 4.0\0");
	n.__exit();
	return;
};

def test_string() -> void
{
	JSONNode n();
	n.set_string("hello\0");
	check(n.is_string(),                             "string: is_string\0");
	check(strcmp(n.as_string(), "hello\0") == 0,     "string: value\0");
	n.set_string("world\0");
	check(strcmp(n.as_string(), "world\0") == 0,     "string: overwrite\0");
	n.__exit();
	return;
};

def test_array() -> void
{
	JSONNode  root();
	JSONNode* c;
	root.set_array();
	check(root.is_array(),        "array: is_array\0");
	check(root.array_len() == 0,  "array: empty len\0");

	c = (JSONNode*)root.array_push_new();
	c.set_int((i64)1);
	c = (JSONNode*)root.array_push_new();
	c.set_int((i64)2);
	c = (JSONNode*)root.array_push_new();
	c.set_int((i64)3);

	check(root.array_len() == 3,                          "array: len 3\0");
	check(((JSONNode*)root.array_get(0)).as_int() == 1,   "array: [0] == 1\0");
	check(((JSONNode*)root.array_get(1)).as_int() == 2,   "array: [1] == 2\0");
	check(((JSONNode*)root.array_get(2)).as_int() == 3,   "array: [2] == 3\0");
	check((u64)root.array_get(3) == 0,                    "array: oob returns null\0");

	root.__exit();
	return;
};

def test_object() -> void
{
	JSONNode  root();
	JSONNode* c;
	root.set_object();
	check(root.is_object(),        "object: is_object\0");
	check(root.object_len() == 0,  "object: empty len\0");

	c = (JSONNode*)root.object_set_new("name\0");
	c.set_string("flux\0");
	c = (JSONNode*)root.object_set_new("version\0");
	c.set_int((i64)1);
	c = (JSONNode*)root.object_set_new("stable\0");
	c.set_bool(true);

	check(root.object_len() == 3,                                              "object: len 3\0");
	check(root.object_has("name\0"),                                           "object: has name\0");
	check(!root.object_has("missing\0"),                                       "object: !has missing\0");
	check(strcmp(((JSONNode*)root.object_get("name\0")).as_string(), "flux\0") == 0, "object: name value\0");
	check(((JSONNode*)root.object_get("version\0")).as_int() == 1,             "object: version value\0");
	check(((JSONNode*)root.object_get("stable\0")).as_bool(),                  "object: stable value\0");

	c = (JSONNode*)root.object_set_new("version\0");
	c.set_int((i64)2);
	check(root.object_len() == 3,                                              "object: len unchanged on overwrite\0");
	check(((JSONNode*)root.object_get("version\0")).as_int() == 2,             "object: overwritten value\0");

	root.__exit();
	return;
};

def test_serialize() -> void
{
	JSONNode   root();
	JSONNode*  c;
	JSONNode*  arr;
	byte[1024] buf;
	int        n;

	root.set_object();
	c = (JSONNode*)root.object_set_new("null_val\0");
	c.set_null();
	c = (JSONNode*)root.object_set_new("bool_val\0");
	c.set_bool(true);
	c = (JSONNode*)root.object_set_new("int_val\0");
	c.set_int((i64)99);
	c = (JSONNode*)root.object_set_new("str_val\0");
	c.set_string("hi\0");
	c = (JSONNode*)root.object_set_new("arr_val\0");
	c.set_array();
	arr = c;
	c = (JSONNode*)arr.array_push_new();
	c.set_int((i64)1);
	c = (JSONNode*)arr.array_push_new();
	c.set_int((i64)2);

	n = serialize(@root, @buf[0], 0, 1024);
	check(n > 0,               "serialize: wrote bytes\0");
	check(buf[0] == '{',       "serialize: starts with {\0");
	check(buf[n - 1] == '}',   "serialize: ends with }\0");

	print("  serialized: \0");
	print(@buf[0]);
	print("\n\0");

	root.__exit();
	return;
};

def test_parse_primitives() -> void
{
	JSONNode   n();
	JSONParser p("42\0");
	p.parse(@n);
	check(p.ok(),             "parse int: ok\0");
	check(n.is_int(),         "parse int: is_int\0");
	check(n.as_int() == 42,   "parse int: value\0");
	n.__exit();

	JSONNode   nf();
	JSONParser pf("3.14\0");
	pf.parse(@nf);
	check(pf.ok(),            "parse float: ok\0");
	check(nf.is_float(),      "parse float: is_float\0");
	check(nf.as_float() > 3.0 & nf.as_float() < 4.0, "parse float: value\0");
	nf.__exit();

	JSONNode   nt();
	JSONParser pt("true\0");
	pt.parse(@nt);
	check(pt.ok(),            "parse true: ok\0");
	check(nt.as_bool(),       "parse true: value\0");
	nt.__exit();

	JSONNode   nfa();
	JSONParser pfa("false\0");
	pfa.parse(@nfa);
	check(pfa.ok(),           "parse false: ok\0");
	check(!nfa.as_bool(),     "parse false: value\0");
	nfa.__exit();

	JSONNode   nn();
	JSONParser pn("null\0");
	pn.parse(@nn);
	check(pn.ok(),            "parse null: ok\0");
	check(nn.is_null(),       "parse null: is_null\0");
	nn.__exit();

	JSONNode   ns();
	JSONParser ps("\"hello\"\0");
	ps.parse(@ns);
	check(ps.ok(),                                    "parse string: ok\0");
	check(strcmp(ns.as_string(), "hello\0") == 0,     "parse string: value\0");
	ns.__exit();

	JSONNode   neg();
	JSONParser pneg("-55\0");
	pneg.parse(@neg);
	check(pneg.ok(),          "parse negative: ok\0");
	check(neg.as_int() == -55,"parse negative: value\0");
	neg.__exit();

	return;
};

def test_parse_array() -> void
{
	JSONNode   root();
	JSONParser p("[1, 2, 3]\0");
	p.parse(@root);
	check(p.ok(),                                           "parse array: ok\0");
	check(root.is_array(),                                  "parse array: is_array\0");
	check(root.array_len() == 3,                            "parse array: len 3\0");
	check(((JSONNode*)root.array_get(0)).as_int() == 1,     "parse array: [0]\0");
	check(((JSONNode*)root.array_get(1)).as_int() == 2,     "parse array: [1]\0");
	check(((JSONNode*)root.array_get(2)).as_int() == 3,     "parse array: [2]\0");
	root.__exit();
	return;
};

def test_parse_object() -> void
{
	JSONNode   root();
	JSONParser p("{\"x\": 10, \"y\": 20}\0");
	p.parse(@root);
	check(p.ok(),                                                "parse object: ok\0");
	check(root.is_object(),                                      "parse object: is_object\0");
	check(root.object_len() == 2,                                "parse object: len 2\0");
	check(((JSONNode*)root.object_get("x\0")).as_int() == 10,    "parse object: x\0");
	check(((JSONNode*)root.object_get("y\0")).as_int() == 20,    "parse object: y\0");
	root.__exit();
	return;
};

def test_parse_nested() -> void
{
	JSONNode   root();
	JSONNode*  name;
	JSONNode*  nums;
	JSONNode*  meta;
	JSONParser p("{\"name\": \"flux\", \"nums\": [1, 2, 3], \"meta\": {\"ok\": true}}\0");
	p.parse(@root);
	check(p.ok(),         "parse nested: ok\0");
	check(root.is_object(),"parse nested: is_object\0");

	name = (JSONNode*)root.object_get("name\0");
	check((u64)name != 0,                              "parse nested: has name\0");
	check(strcmp(name.as_string(), "flux\0") == 0,     "parse nested: name value\0");

	nums = (JSONNode*)root.object_get("nums\0");
	check((u64)nums != 0,                              "parse nested: has nums\0");
	check(nums.is_array(),                             "parse nested: nums is_array\0");
	check(nums.array_len() == 3,                       "parse nested: nums len\0");
	check(((JSONNode*)nums.array_get(2)).as_int() == 3,"parse nested: nums[2]\0");

	meta = (JSONNode*)root.object_get("meta\0");
	check((u64)meta != 0,                              "parse nested: has meta\0");
	check(meta.is_object(),                            "parse nested: meta is_object\0");
	check(((JSONNode*)meta.object_get("ok\0")).as_bool(),"parse nested: meta.ok\0");

	root.__exit();
	return;
};

def test_roundtrip() -> void
{
	JSONNode   built();
	JSONNode   parsed();
	JSONNode*  c;
	byte[512]  buf;
	int        n;

	built.set_object();
	c = (JSONNode*)built.object_set_new("a\0");
	c.set_int((i64)7);
	c = (JSONNode*)built.object_set_new("b\0");
	c.set_string("test\0");

	n = serialize(@built, @buf[0], 0, 512);
	check(n > 0, "roundtrip: serialized\0");

	JSONParser p(@buf[0]);
	p.parse(@parsed);
	check(p.ok(),                                                             "roundtrip: parse ok\0");
	check(((JSONNode*)parsed.object_get("a\0")).as_int() == 7,                "roundtrip: a == 7\0");
	check(strcmp(((JSONNode*)parsed.object_get("b\0")).as_string(), "test\0") == 0, "roundtrip: b == test\0");

	built.__exit();
	parsed.__exit();
	return;
};

def main() -> int
{
	byte[16] num_buf;

	print("=== json.fx tests ===\n\0");

	test_null();
	test_bool();
	test_int();
	test_float();
	test_string();
	test_array();
	test_object();
	test_serialize();
	test_parse_primitives();
	test_parse_array();
	test_parse_object();
	test_parse_nested();
	test_roundtrip();

	print("\n\0");
	standard::strings::i32str(g_pass, @num_buf[0]);
	print(@num_buf[0]);
	print(" passed, \0");
	standard::strings::i32str(g_fail, @num_buf[0]);
	print(@num_buf[0]);
	print(" failed\n\0");

	return g_fail;
};
