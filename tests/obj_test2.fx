#import <standard.fx>;

using standard::io::console;

object A
{
	int x = 10;
	this
	{
		.x = 20;
	};
	__init()->this->this;
	__expr()->A*->this;
	__exit()->void->;
};

main() -> int
{
	->0;
};