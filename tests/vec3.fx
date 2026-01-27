#import "standard.fx";

object Vector3
{
    float x;
    float y;
    float z;
    
    def __init(float x, float y, float z) -> this
    {
        this.x = x;
        this.y = y;
        this.z = z;
        return this;
    };

    def __exit() -> void
    {
        return void;
    };
    
    def length() -> float {
        return (this.x^2 + this.y^2 + this.z^2) ^ 0.5;
    };
};

def main() -> int
{
	return 0;
};