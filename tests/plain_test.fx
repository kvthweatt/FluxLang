#import "standard.fx", "strfuncs.fx";

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

	print(buf);

	return 0;
};