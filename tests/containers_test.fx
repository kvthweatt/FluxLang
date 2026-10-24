#import <standard.fx>;
#import <containers.fx>;
using standard::io::console;
using standard::containers;

struct P { int x, y; };

operator (P a, P b) [<] -> bool { return a.x < b.x; };

def main() -> int
{
    DynArray<int> d();
    int i;
    while (i < 20) { d.push(i * i); i++; };
    int x;
    d.pop(@x);
    d.remove_at(0);
    d.insert(1, 777);
    println(f"dynamic array {d.len()} {d.at(1)} {x} {d.index_of(777)}");

    RingBuffer<int> r();
    r.push_back(1); r.push_back(2); r.push_front(0); r.push_front(-1);
    int a, b;
    r.pop_front(@a); r.pop_back(@b);
    println(f"ring {r.len()} {a} {b} {r.at(0)} {r.at(1)}");

    MinHeap<int> h();
    int k = 30;
    while (k > 0) { h.push((k * 7) % 31); k--; };
    int m, prev = -1, ok = 1;
    while (h.pop(@m)) { if (m < prev) { ok = 0; }; prev = m; };
    println(f"heap sorted={ok}");

    HashMap<int, int> hm();
    i = 0;
    while (i < 1000) { hm.put(i * 3, i); i++; };
    i = 0;
    while (i < 1000) { if (i % 2 == 0) { hm.remove(i * 3); }; i++; };
    int got;
    bool f1 = hm.get(3, @got);
    bool f2 = hm.get(6, @got);
    println(f"hashmap {hm.len()} {f1} {f2} {hm.get_or(9, -1)} {hm.get_or(12, -1)}");

    HashSet<long> s();
    i = 0;
    while (i < 100) { s.add((long)(i % 10)); i++; };
    println(f"set {s.len()} {s.contains(3)} {s.contains(11)}");

    StrHashMap<int> sm();
    sm.put("alpha", 1); sm.put("beta", 2); sm.put("gamma", 3); sm.put("alpha", 10);
    sm.remove("beta");
    int sa = sm.get_or("alpha", 0), sb = sm.get_or("beta", -1);
    bool sg = sm.contains("gamma");
    println(f"strmap {sm.len()} {sa} {sb} {sg}");
    return 0;
};
