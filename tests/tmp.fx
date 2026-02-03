#import "standard.fx";

def compute_gas_volume(float pressure, float temperature, float moles) -> float
{
    float gas_const = 8.3144621;
    //Using PV = nRT, so V = nRT / P;
    float volume = (moles * gas_const * temperature) / pressure;
    return volume;
};

def main() -> int
{
    float gv = compute_gas_volume(3000,400,50);
    print(gv);
    print();
    return 0;
};