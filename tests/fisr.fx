#import "standard.fx";

def fisr(float number) -> float
{
	i64 i;
	float x2;
    float y;
	const float threehalfs = 1.5;

	x2 = number * 0.5;
	y  = number;
	i  = *(i64*)@y;                             // evil floating point bit level hacking
	i  = (i64)0x5F3759DF - ( i >> 1 );          // what the fuck?
	y  = *(float*)@i;
	y  = y * ( threehalfs - ( x2 * y * y ) );   // 1st iteration
//	y  = y * ( threehalfs - ( x2 * y * y ) );   // 2nd iteration, this can be removed

	return y;
};

def main() -> int
{
    float y = fisr(5.0);
    //noopstr s = f"{y}\0";
	return 0;
};