#import <standard.fx>;

using standard::io::console,
      standard::io::file;


def main(int argc, byte** argv) -> int
{
	switch(argc)
	{
		case (2)
		{
            file sf(argv[1], "rb");
            defer sf.__exit();

            if (sf.error_state is void)
            {
                print(f"File opened.

\t=== CONTENTS ===\n
{sf.contents}
\t=== /CONTENTS/ ===\n");
                //return 0;
            }
            else
            {
                println("Error opening file.");
            };

			print(f"{argv[1]}");
		}
		default
		{
			print("Usage: fpp [source.fx]\n");
		};
	};
    print("Got here!\n");
	return 0;
};