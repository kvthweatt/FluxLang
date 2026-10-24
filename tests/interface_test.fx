#import <standard.fx>;

using standard::io::console;

trait Queryable  { def query(byte* sql) -> byte*; };
trait Connectable { def connect() -> bool, disconnect() -> bool; };

interface Database(A: Connectable, B: Queryable)
{
    A : B { connect() -> bool };
};

object Client, Store;

object Store
{
    def __init() -> this -> this;
    def __exit() -> void {};
    def __expr() -> Store* -> this;

    def query(byte* sql) -> byte* -> sql;
    def connect() -> bool -> true;
    def disconnect() -> bool -> true;
};

object Client
{
    def __init() -> this -> this;
    def __exit() -> void {};
    def __expr() -> Client* -> this;

    def connect() -> bool -> true;
    def disconnect() -> bool -> true;

    def go(Store* s) -> void
    {
        s.connect();      // listed in A : B, allowed
        s.disconnect();   // not listed, compile error
    };
} : Database(this, Store);

def main() -> int
{
    Client c();
    Store  s();
    return 0;
};