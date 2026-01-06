import "standard.fx";


object testobject
{
    noopstr m = "Goodbye!";
	def __init() -> this
    {
        win_print("Hello from testobj", 18);
        wpnl();
        return this;
    };
	def __exit() -> void
    {
        noopstr t = "Goodbye!";
        win_print(t,8);
        //win_print(this.m,8);  // fails
        //win_print(@this.m,8); // fails
        return void;
    };
};


def main() -> int
{
    testobject t();
    t.__exit();     // Had to manually call. We're memory leaking.
	return 0;
};