#import <standard.fx>;

using standard::io::console;

byte b = 97b;

trait Queryable { def query(byte* sql) -> byte*; };
trait Connectable { def connect() -> bool; };

interface Database(A: Connectable, B: Queryable)
{
    A : B
    {
        query()    -> byte*,
        disconnect() -> void
    };

    B(A)
    {
        query(byte* sql) -> byte*       // can do B.query(A.result());
    };

    A -> B
    {
        result() -> byte*               // can 
    };
};

object Client, Store;

object Store
{
    def __init() -> this { return this; };
    def __exit() -> void {};
    def __expr() -> int { return 0; };
    def query(byte* sql) -> byte* { return sql; };
    def disconnect() -> void {};

    def fetch(Client* c) -> byte*
    {
        // A -> B: Client.result() called from inside Store -- should be allowed
        byte* r = c.result();
        return r;
    };
};

object Client
{
    def __init() -> this { return this; };
    def __exit() -> void {};
    def __expr() -> int { return 0; };
    def connect() -> bool { return true; };
    def result()  -> byte* { return "data\0"; };
} : Database(this, Store);

def main() -> int
{
    Client c();
    Store  s();

    // B(A): passing return of Client method as arg to Store -- should be allowed
    byte* out = s.query(c.result());

    // A : B: Client calling Store methods -- should be allowed
    c.connect();

    return 0;
};