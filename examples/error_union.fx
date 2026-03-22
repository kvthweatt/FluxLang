#import "standard.fx";

using standard::io::console;

enum ErrorUnionEnum
{
    INACTIVE,
	INT_ACTIVE,
	LONG_ACTIVE,
	BOOL_ACTIVE,
	CHAR_ACTIVE,
	FLOAT_ACTIVE,
	DOUBLE_ACTIVE	
};

union ErrorUnion
{
	int  iRval;
	long lRval;
	bool bRval;
	char cRval;
	float fRval;
	double dRval;
} ErrorUnionEnum;


def foo() -> ErrorUnion
{
    ErrorUnion err;

    err.bRval = false; // Set bool to active element
    err._ = ErrorUnionEnum.BOOL_ACTIVE;

    return err;
};


def main() -> int
{
    ErrorUnion e = foo();

    switch (e._)
    {
        case (ErrorUnionEnum.INT_ACTIVE)
        {
            print("Integer active in error union!\n\0");
        }
        case (ErrorUnionEnum.LONG_ACTIVE)
        {
            print("Long active in error union!\n\0");
        }
        case (ErrorUnionEnum.BOOL_ACTIVE)
        {
            print("Bool active in error union!\n\0");
        }
        case (ErrorUnionEnum.CHAR_ACTIVE)
        {
            print("Char active in error union!\n\0");
        }
        case (ErrorUnionEnum.FLOAT_ACTIVE)
        {
            print("Float active in error union!\n\0");
        }
        case (ErrorUnionEnum.DOUBLE_ACTIVE)
        {
            print("Double active in error union!\n\0");
        }

        default { print("No active tag set!\n\0"); };
    };
	return 0;
};