// Author: Karac V. Thweatt

// json.fx - JSON parse, build, and serialize library.
//
// JSONNode   - tagged value node (null/bool/int/float/string/array/object)
// JSONArray  - growable array of void* node pointers
// JSONObject - ordered key/value store
// JSONParser - tokenizing recursive-descent parser
//
// All locals declared at function top. All variables zero-initialized.
// node_free() is used inside JSONNode.__exit() to avoid self-reference.
// Methods that return child nodes return void*; caller casts to JSONNode*.

#ifndef FLUX_STANDARD
#import "standard.fx";
#endif;

#ifndef FLUX_JSON
#def FLUX_JSON 1;

namespace json
{
	const int JSON_NULL   = 0,
	          JSON_BOOL   = 1,
	          JSON_INT    = 2,
	          JSON_FLOAT  = 3,
	          JSON_STRING = 4,
	          JSON_ARRAY  = 5,
	          JSON_OBJECT = 6;

	// =========================================================================
	// JSONArray - growable void* array
	// =========================================================================

	object JSONArray
	{
		void*  buf;
		size_t len, cap;

		def __init() -> this
		{
			this.cap = 8;
			this.buf = (@)fmalloc(this.cap * 8);
			return this;
		};

		def __exit() -> void
		{
			if ((u64)this.buf != 0)
			{
				ffree((u64)this.buf);
				this.buf = (@)0;
			};
			return;
		};

		def _grow() -> bool
		{
			void*  nb;
			size_t new_cap;
			new_cap = this.cap * 2;
			nb      = (@)fmalloc(new_cap * 8);
			if ((u64)nb == 0) { return false; };
			memcpy(nb, this.buf, this.cap * 8);
			ffree((u64)this.buf);
			this.buf = nb;
			this.cap = new_cap;
			return true;
		};

		def push(void* node) -> bool
		{
			void** slot;
			if (this.len >= this.cap)
			{
				if (!this._grow()) { return false; };
			};
			slot  = (void**)this.buf + this.len;
			*slot = node;
			this.len++;
			return true;
		};

		def get(size_t i) -> void*
		{
			void** slot;
			if (i >= this.len) { return (@)0; };
			slot = (void**)this.buf + i;
			return *slot;
		};
	};

	// =========================================================================
	// JSONObject - ordered key/value pairs, keys heap-copied
	// =========================================================================

	object JSONObject
	{
		void*  keys, vals;
		size_t len, cap;

		def __init() -> this
		{
			this.cap  = 8;
			this.keys = (@)fmalloc(this.cap * 8);
			this.vals = (@)fmalloc(this.cap * 8);
			return this;
		};

		def __exit() -> void
		{
			byte** ks;
			size_t i;
			if ((u64)this.keys != 0)
			{
				ks = (byte**)this.keys;
				while (i < this.len)
				{
					if ((u64)ks[i] != 0) { ffree((u64)ks[i]); };
					i++;
				};
				ffree((u64)this.keys);
				this.keys = (@)0;
			};
			if ((u64)this.vals != 0)
			{
				ffree((u64)this.vals);
				this.vals = (@)0;
			};
			return;
		};

		def _grow() -> bool
		{
			void*  nk, nv;
			size_t new_cap;
			new_cap = this.cap * 2;
			nk      = (@)fmalloc(new_cap * 8);
			if ((u64)nk == 0) { return false; };
			nv = (@)fmalloc(new_cap * 8);
			if ((u64)nv == 0) { ffree((u64)nk); return false; };
			memcpy(nk, this.keys, this.cap * 8);
			memcpy(nv, this.vals, this.cap * 8);
			ffree((u64)this.keys);
			ffree((u64)this.vals);
			this.keys = nk;
			this.vals = nv;
			this.cap  = new_cap;
			return true;
		};

		def set(byte* key, void* val) -> bool
		{
			byte** ks;
			void** vs;
			byte*  kc;
			size_t i;
			int    kl, el, j;
			bool   match;
			ks = (byte**)this.keys;
			vs = (void**)this.vals;
			kl = standard::strings::strlen(key);
			while (i < this.len)
			{
				el    = standard::strings::strlen(ks[i]);
				match = el == kl;
				if (match)
				{
					while (j < kl)
					{
						if (ks[i][j] != key[j]) { match = false; break; };
						j = j + 1;
					};
				};
				if (match) { vs[i] = val; return true; };
				i++;
			};
			if (this.len >= this.cap)
			{
				if (!this._grow()) { return false; };
				ks = (byte**)this.keys;
				vs = (void**)this.vals;
			};
			kc = (byte*)fmalloc((u64)(kl + 1));
			if ((u64)kc == 0) { return false; };
			while (j <= kl) { kc[j] = key[j]; j = j + 1; };
			ks[this.len] = kc;
			vs[this.len] = val;
			this.len++;
			return true;
		};

		def get(byte* key) -> void*
		{
			byte** ks;
			void** vs;
			size_t i;
			int    kl, el, j;
			bool   match;
			ks = (byte**)this.keys;
			vs = (void**)this.vals;
			kl = standard::strings::strlen(key);
			while (i < this.len)
			{
				el    = standard::strings::strlen(ks[i]);
				match = el == kl;
				if (match)
				{
					while (j < kl)
					{
						if (ks[i][j] != key[j]) { match = false; break; };
						j = j + 1;
					};
				};
				if (match) { return vs[i]; };
				i++;
			};
			return (@)0;
		};

		def has(byte* key) -> bool
		{
			return (u64)this.get(key) != 0;
		};

		def key_at(size_t i) -> byte*
		{
			byte** ks;
			if (i >= this.len) { return (byte*)0; };
			ks = (byte**)this.keys;
			return ks[i];
		};

		def val_at(size_t i) -> void*
		{
			void** vs;
			if (i >= this.len) { return (@)0; };
			vs = (void**)this.vals;
			return vs[i];
		};
	};

	// node_free forward declaration — defined after JSONNode.
	def node_free(void* p) -> void;

	// =========================================================================
	// JSONNode
	// =========================================================================

	object JSONNode
	{
		int    type;
		bool   b;
		i64    i;
		double f;
		byte*  s;
		JSONArray  arr;
		JSONObject obj;

		def __init() -> this
		{
			return this;
		};

		def __exit() -> void
		{
			void*  child;
			size_t k, n;
			if (this.type == JSON_STRING)
			{
				if ((u64)this.s != 0)
				{
					ffree((u64)this.s);
					this.s = (byte*)0;
				};
			};
			if (this.type == JSON_ARRAY)
			{
				n = this.arr.len;
				while (k < n)
				{
					child = this.arr.get(k);
					if ((u64)child != 0) { node_free(child); };
					k++;
				};
				this.arr.__exit();
			};
			if (this.type == JSON_OBJECT)
			{
				n = this.obj.len;
				while (k < n)
				{
					child = this.obj.val_at(k);
					if ((u64)child != 0) { node_free(child); };
					k++;
				};
				this.obj.__exit();
			};
			return;
		};

		def is_null()   -> bool { return this.type == JSON_NULL;   };
		def is_bool()   -> bool { return this.type == JSON_BOOL;   };
		def is_int()    -> bool { return this.type == JSON_INT;    };
		def is_float()  -> bool { return this.type == JSON_FLOAT;  };
		def is_string() -> bool { return this.type == JSON_STRING; };
		def is_array()  -> bool { return this.type == JSON_ARRAY;  };
		def is_object() -> bool { return this.type == JSON_OBJECT; };

		def set_null() -> void
		{
			this.type = JSON_NULL;
			return;
		};

		def set_bool(bool v) -> void
		{
			this.type = JSON_BOOL;
			this.b    = v;
			return;
		};

		def set_int(i64 v) -> void
		{
			this.type = JSON_INT;
			this.i    = v;
			return;
		};

		def set_float(double v) -> void
		{
			this.type = JSON_FLOAT;
			this.f    = v;
			return;
		};

		def set_string(byte* src) -> bool
		{
			byte* kc;
			int   n, j;
			n  = standard::strings::strlen(src);
			kc = (byte*)fmalloc((u64)(n + 1));
			if ((u64)kc == 0) { return false; };
			while (j <= n) { kc[j] = src[j]; j = j + 1; };
			if ((u64)this.s != 0) { ffree((u64)this.s); };
			this.s    = kc;
			this.type = JSON_STRING;
			return true;
		};

		def set_array() -> void
		{
			this.type = JSON_ARRAY;
			this.arr.__init();
			return;
		};

		def set_object() -> void
		{
			this.type = JSON_OBJECT;
			this.obj.__init();
			return;
		};

		def as_bool() -> bool
		{
			if (this.type == JSON_BOOL) { return this.b; };
			if (this.type == JSON_INT)  { return this.i != 0; };
			return false;
		};

		def as_int() -> i64
		{
			if (this.type == JSON_INT)   { return this.i; };
			if (this.type == JSON_FLOAT) { return (i64)this.f; };
			if (this.type == JSON_BOOL)  { return this.b ? 1 : 0; };
			return 0;
		};

		def as_float() -> double
		{
			if (this.type == JSON_FLOAT) { return this.f; };
			if (this.type == JSON_INT)   { return (double)this.i; };
			return 0.0;
		};

		def as_string() -> byte*
		{
			if (this.type == JSON_STRING) { return this.s; };
			return (byte*)0;
		};

		def array_push_new() -> void*
		{
			void* child;
			if (this.type != JSON_ARRAY) { return (@)0; };
			child = (@)fmalloc(sizeof(JSONNode) / 8);
			if ((u64)child == 0) { return (@)0; };
			((JSONNode*)child).__init();
			if (!this.arr.push(child))
			{
				((JSONNode*)child).__exit();
				ffree((u64)child);
				return (@)0;
			};
			return child;
		};

		def array_len() -> size_t
		{
			if (this.type != JSON_ARRAY) { return 0; };
			return this.arr.len;
		};

		def array_get(size_t i) -> void*
		{
			if (this.type != JSON_ARRAY) { return (@)0; };
			return this.arr.get(i);
		};

		def object_set_new(byte* key) -> void*
		{
			void* child;
			if (this.type != JSON_OBJECT) { return (@)0; };
			child = (@)fmalloc(sizeof(JSONNode) / 8);
			if ((u64)child == 0) { return (@)0; };
			((JSONNode*)child).__init();
			if (!this.obj.set(key, child))
			{
				((JSONNode*)child).__exit();
				ffree((u64)child);
				return (@)0;
			};
			return child;
		};

		def object_get(byte* key) -> void*
		{
			if (this.type != JSON_OBJECT) { return (@)0; };
			return this.obj.get(key);
		};

		def object_has(byte* key) -> bool
		{
			if (this.type != JSON_OBJECT) { return false; };
			return this.obj.has(key);
		};

		def object_len() -> size_t
		{
			if (this.type != JSON_OBJECT) { return 0; };
			return this.obj.len;
		};

		def object_key_at(size_t i) -> byte*
		{
			if (this.type != JSON_OBJECT) { return (byte*)0; };
			return this.obj.key_at(i);
		};

		def object_val_at(size_t i) -> void*
		{
			if (this.type != JSON_OBJECT) { return (@)0; };
			return this.obj.val_at(i);
		};
	};

	// node_free definition — now JSONNode is fully defined, safe to use.
	def node_free(void* p) -> void
	{
		JSONNode* n;
		n = (JSONNode*)p;
		n.__exit();
		ffree((u64)p);
		return;
	};

	// =========================================================================
	// Serializer
	// =========================================================================

	def _wc(byte* buf, int pos, int cap, char c) -> int
	{
		if (pos < cap - 1) { buf[pos] = (byte)c; pos = pos + 1; };
		buf[pos] = '\x00';
		return pos;
	};

	def _ws(byte* buf, int pos, int cap, byte* src) -> int
	{
		int i;
		while (src[i] != '\x00' & pos < cap - 1)
		{
			buf[pos] = src[i];
			pos = pos + 1;
			i   = i + 1;
		};
		buf[pos] = '\x00';
		return pos;
	};

	def _we(byte* buf, int pos, int cap, byte* src) -> int
	{
		int  i;
		char c;
		while (src[i] != '\x00')
		{
			c = (char)src[i];
			if      (c == '"')  { pos = _wc(buf, pos, cap, '\\'); pos = _wc(buf, pos, cap, '"');  }
			elif    (c == '\\') { pos = _wc(buf, pos, cap, '\\'); pos = _wc(buf, pos, cap, '\\'); }
			elif    (c == '\n') { pos = _wc(buf, pos, cap, '\\'); pos = _wc(buf, pos, cap, 'n');  }
			elif    (c == '\r') { pos = _wc(buf, pos, cap, '\\'); pos = _wc(buf, pos, cap, 'r');  }
			elif    (c == '\t') { pos = _wc(buf, pos, cap, '\\'); pos = _wc(buf, pos, cap, 't');  }
			else                { pos = _wc(buf, pos, cap, c); };
			i = i + 1;
		};
		return pos;
	};

	def serialize(JSONNode* node, byte* buf, int pos, int cap) -> int
	{
		byte[32]  num_buf;
		size_t    k, n;
		JSONNode* child;

		if ((u64)node == 0) { return _ws(buf, pos, cap, "null\0"); };

		switch (node.type)
		{
			case (JSON_NULL) { pos = _ws(buf, pos, cap, "null\0"); }
			case (JSON_BOOL)
			{
				if (node.b) { pos = _ws(buf, pos, cap, "true\0"); }
				else        { pos = _ws(buf, pos, cap, "false\0"); };
			}
			case (JSON_INT)
			{
				standard::strings::i64str(node.i, @num_buf[0]);
				pos = _ws(buf, pos, cap, @num_buf[0]);
			}
			case (JSON_FLOAT)
			{
				standard::strings::dbl2str(node.f, @num_buf[0], 6);
				pos = _ws(buf, pos, cap, @num_buf[0]);
			}
			case (JSON_STRING)
			{
				pos = _wc(buf, pos, cap, '"');
				pos = _we(buf, pos, cap, node.s);
				pos = _wc(buf, pos, cap, '"');
			}
			case (JSON_ARRAY)
			{
				n   = node.arr.len;
				pos = _wc(buf, pos, cap, '[');
				while (k < n)
				{
					if (k > 0) { pos = _wc(buf, pos, cap, ','); };
					child = (JSONNode*)node.arr.get(k);
					pos   = serialize(child, buf, pos, cap);
					k++;
				};
				pos = _wc(buf, pos, cap, ']');
			}
			case (JSON_OBJECT)
			{
				n   = node.obj.len;
				pos = _wc(buf, pos, cap, '{');
				while (k < n)
				{
					if (k > 0) { pos = _wc(buf, pos, cap, ','); };
					pos   = _wc(buf, pos, cap, '"');
					pos   = _we(buf, pos, cap, node.obj.key_at(k));
					pos   = _wc(buf, pos, cap, '"');
					pos   = _wc(buf, pos, cap, ':');
					child = (JSONNode*)node.obj.val_at(k);
					pos   = serialize(child, buf, pos, cap);
					k++;
				};
				pos = _wc(buf, pos, cap, '}');
			}
			default {};
		};

		return pos;
	};

	// =========================================================================
	// JSONParser
	// =========================================================================

	object JSONParser
	{
		byte* src;
		int   pos, len, error;

		def __init(byte* text) -> this
		{
			this.src = text;
			this.len = standard::strings::strlen(text);
			return this;
		};

		def __exit() -> void
		{
			return;
		};

		def ok() -> bool
		{
			return this.error == 0;
		};

		def _skip_ws() -> void
		{
			char c;
			while (this.pos < this.len)
			{
				c = (char)this.src[this.pos];
				if (c == ' ' | c == '\t' | c == '\n' | c == '\r')
				{
					this.pos = this.pos + 1;
				}
				else { break; };
			};
			return;
		};

		def _peek() -> char
		{
			if (this.pos >= this.len) { return '\x00'; };
			return (char)this.src[this.pos];
		};

		def _adv() -> char
		{
			char c;
			if (this.pos >= this.len) { return '\x00'; };
			c        = (char)this.src[this.pos];
			this.pos = this.pos + 1;
			return c;
		};

		def _parse_string(JSONNode* node) -> bool
		{
			byte* s;
			int   start, slen, j;
			char  c;
			this._adv();
			start = this.pos;
			while (this.pos < this.len)
			{
				c = (char)this.src[this.pos];
				if (c == '"') { break; };
				if (c == '\\') { this.pos = this.pos + 1; };
				this.pos = this.pos + 1;
				slen     = slen + 1;
			};
			if (this._peek() != '"') { this.error = 1; return false; };
			s = (byte*)fmalloc((u64)(slen + 1));
			if ((u64)s == 0) { this.error = 2; return false; };
			this.pos = start;
			while (j < slen)
			{
				c = (char)this.src[this.pos];
				if (c == '\\')
				{
					this.pos = this.pos + 1;
					c = (char)this.src[this.pos];
					if      (c == '"')  { s[j] = '"';  }
					elif    (c == '\\') { s[j] = '\\'; }
					elif    (c == 'n')  { s[j] = '\n'; }
					elif    (c == 'r')  { s[j] = '\r'; }
					elif    (c == 't')  { s[j] = '\t'; }
					else                { s[j] = (byte)c; };
				}
				else { s[j] = (byte)c; };
				this.pos = this.pos + 1;
				j = j + 1;
			};
			s[slen] = '\x00';
			this._adv();
			if ((u64)node.s != 0) { ffree((u64)node.s); };
			node.s    = s;
			node.type = JSON_STRING;
			return true;
		};

		def _parse_number(JSONNode* node) -> bool
		{
			bool   is_float, neg;
			i64    iv;
			double fv, fdiv;
			char   c;
			c = this._peek();
			if (c == '-') { neg = true; this._adv(); };
			while (this.pos < this.len)
			{
				c = (char)this.src[this.pos];
				if (c >= '0' & c <= '9')
				{
					iv = iv * 10 + (c - '0');
					this.pos = this.pos + 1;
				}
				else { break; };
			};
			if (this._peek() == '.')
			{
				is_float = true;
				fdiv     = 1.0;
				fv       = (double)iv;
				this._adv();
				while (this.pos < this.len)
				{
					c = (char)this.src[this.pos];
					if (c >= '0' & c <= '9')
					{
						fdiv = fdiv * 10.0;
						fv   = fv + (double)(c - '0') / fdiv;
						this.pos = this.pos + 1;
					}
					else { break; };
				};
			};
			if (is_float) { node.set_float(neg ? -fv : fv); }
			else          { node.set_int(neg ? -iv : iv);   };
			return true;
		};

		def _parse_value(JSONNode* node) -> bool;

		def _parse_array(JSONNode* node) -> bool
		{
			void* child;
			node.set_array();
			this._adv();
			this._skip_ws();
			if (this._peek() == ']') { this._adv(); return true; };
			while (this.pos < this.len)
			{
				child = node.array_push_new();
				if ((u64)child == 0) { this.error = 2; return false; };
				if (!this._parse_value((JSONNode*)child)) { return false; };
				this._skip_ws();
				if (this._peek() == ']') { this._adv(); return true; };
				if (this._peek() != ',') { this.error = 1; return false; };
				this._adv();
				this._skip_ws();
			};
			this.error = 1;
			return false;
		};

		def _parse_object(JSONNode* node) -> bool
		{
			byte[256] key_buf;
			void*     child;
			int       ki;
			char      c;
			node.set_object();
			this._adv();
			this._skip_ws();
			if (this._peek() == '}') { this._adv(); return true; };
			while (this.pos < this.len)
			{
				this._skip_ws();
				if (this._peek() != '"') { this.error = 1; return false; };
				this._adv();
				ki = 0;
				while (this.pos < this.len)
				{
					c = (char)this.src[this.pos];
					if (c == '"') { break; };
					if (c == '\\') { this.pos = this.pos + 1; c = (char)this.src[this.pos]; };
					if (ki < 255) { key_buf[ki] = (byte)c; ki = ki + 1; };
					this.pos = this.pos + 1;
				};
				key_buf[ki] = '\x00';
				if (this._peek() != '"') { this.error = 1; return false; };
				this._adv();
				this._skip_ws();
				if (this._peek() != ':') { this.error = 1; return false; };
				this._adv();
				this._skip_ws();
				child = node.object_set_new(@key_buf[0]);
				if ((u64)child == 0) { this.error = 2; return false; };
				if (!this._parse_value((JSONNode*)child)) { return false; };
				this._skip_ws();
				if (this._peek() == '}') { this._adv(); return true; };
				if (this._peek() != ',') { this.error = 1; return false; };
				this._adv();
			};
			this.error = 1;
			return false;
		};

		def _parse_value(JSONNode* node) -> bool
		{
			char c;
			this._skip_ws();
			c = this._peek();
			if      (c == '"')                          { return this._parse_string(node); }
			elif    (c == '[')                          { return this._parse_array(node);  }
			elif    (c == '{')                          { return this._parse_object(node); }
			elif    (c == 't') { this.pos = this.pos + 4; node.set_bool(true);  return true; }
			elif    (c == 'f') { this.pos = this.pos + 5; node.set_bool(false); return true; }
			elif    (c == 'n') { this.pos = this.pos + 4; node.set_null();      return true; }
			elif    (c == '-' | (c >= '0' & c <= '9')) { return this._parse_number(node); };
			this.error = 1;
			return false;
		};

		def parse(JSONNode* node) -> bool
		{
			return this._parse_value(node);
		};
	};
};

#endif;
