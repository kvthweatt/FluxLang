struct UART_Registers {
    unsigned data{8:32} DR;           // Data register
    unsigned data{8:32} RSR_ECR;      // Status register
    unsigned data{32:32}[4] reserved1;
    unsigned data{8:32} FR;           // Flag register
    unsigned data{32:32} reserved2;
    unsigned data{8:32} ILPR;         // IrDA register
    unsigned data{16:32} IBRD;        // Baud rate (integer)
    unsigned data{6:32} FBRD;         // Baud rate (fractional)
    unsigned data{8:32} LCR_H;        // Line control
    unsigned data{16:32} CR;          // Control register
};

def main() -> int
{
    UART_Registers uaregs1, uaregs2;
    return 0;
};