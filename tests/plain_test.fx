#import ///"standard.fx", ///"strfuncs.fx";

        object Random
        {
            i64 seed;
            
            def __init() -> this
            {
                this.seed = (i64*)12345;
                return this;
            };
            
            def __init(i64 seed) -> this
            {
                if (seed == 0) {seed = 12345;};
                this.seed = seed & 0x7FFFFFFF;
                return this;
            };
            
            def next_i8() -> i8
            {
                this.seed = (this.seed * 1103515245 + 12345) & 0x7FFFFFFF;
                return (this.seed & 0xFF);
            };
            
            def next_i16() -> i16
            {
                this.seed = (this.seed * 1103515245 + 12345) & 0x7FFFFFFF;
                return (i16)(this.seed & 0xFFFF);
            };
            
            def next_i32() -> i32
            {
                this.seed = (this.seed * 1103515245 + 12345) & 0x7FFFFFFF;
                return (i32)(this.seed & 0xFFFFFFFF);
            };
            
            def next_i64() -> i64
            {
                this.seed = (this.seed * 1103515245 + 12345) & 0x7FFFFFFF;
                i64 high = this.next_i32();
                i64 low = this.next_i32();
                return (high << 32) | low;
            };
            
            def next_float() -> float
            {
                return (float)this.next_i32() / 2147483647.0;
            };
            
            def next_range_i8(i8 min_val, i8 max_val) -> i8
            {
                i8 range = max_val - min_val + 1;
                return min_val + (this.next_i8() % range);
            };
            
            def next_range_i16(i16 min_val, i16 max_val) -> i16
            {
                i16 range = max_val - min_val + 1;
                return min_val + (this.next_i16() % range);
            };
            
            def next_range_i32(i32 min_val, i32 max_val) -> i32
            {
                i32 range = max_val - min_val + 1;
                return min_val + (this.next_i32() % range);
            };
            
            def next_range_i64(i64 min_val, i64 max_val) -> i64
            {
                i64 range = max_val - min_val + 1;
                return min_val + (this.next_i64() % range);
            };
            
            def next_range_float(float min_val, float max_val) -> float
            {
                return min_val + this.next_float() * (max_val - min_val);
            };
            
            def next_bool() -> bool
            {
                return (this.next_i32() & 1) == 1;
            };
        };


struct vec3
{
    float x;
    float y;
    float z;
};

def main() -> int
{
	byte[64] buf;

	vec3 v = {10.0,20.0,30.0};

	v.x = 300.01;

	int x = float2str(v.x,buf,2);

	//print(buf);

	return 0;
};