#import "standard.fx", "redrandom.fx";

using standard::random;

// ============================================================================
// Blackjack - OOP style
// ============================================================================

// A card is an int 0..51.
// suit  = card / 13   (0=clubs 1=diamonds 2=hearts 3=spades)
// rank  = card % 13   (0=A 1=2 .. 9=10 10=J 11=Q 12=K)

// ============================================================================
// Hand — holds cards and computes its own value
// ============================================================================

object Hand
{
    int[11] cards;
    int     count;

    def __init() -> this
    {
        this.count = 0;
        return this;
    };

    def __exit() -> void
    {
        return;
    };

    def clear() -> void
    {
        this.count = 0;
    };

    def add(int card) -> void
    {
        this.cards[this.count] = card;
        this.count = this.count + 1;
    };

    def value() -> int
    {
        int total = 0;
        int aces  = 0;
        int i     = 0;

        while (i < this.count)
        {
            int rank = this.cards[i] % 13;
            int v;
            if (rank == 0)       { v = 11; }
            elif (rank >= 9)     { v = 10; }
            else                 { v = rank + 1; };
            total = total + v;
            if (rank == 0) { aces = aces + 1; };
            i = i + 1;
        };

        while (total > 21 & aces > 0)
        {
            total = total - 10;
            aces  = aces  - 1;
        };

        return total;
    };

    def is_bust() -> bool
    {
        return this.value() > 21;
    };

    def is_blackjack() -> bool
    {
        return this.count == 2 & this.value() == 21;
    };

    def print_cards(bool hide_first) -> void
    {
        int i = 0;
        while (i < this.count)
        {
            if (i == 0 & hide_first)
            {
                print("[?]\0");
            }
            else
            {
                int card = this.cards[i];
                int rank = card % 13;
                int suit = card / 13;

                print("[\0");

                if (rank == 0)       { print("A\0"); }
                elif (rank == 9)     { print("10\0"); }
                elif (rank == 10)    { print("J\0"); }
                elif (rank == 11)    { print("Q\0"); }
                elif (rank == 12)    { print("K\0"); }
                else
                {
                    // ranks 1-8 map to face values 2-9
                    print(rank + 1);
                };

                if (suit == 0)      { print("C\0"); }
                elif (suit == 1)    { print("D\0"); }
                elif (suit == 2)    { print("H\0"); }
                else                { print("S\0"); };

                print("]\0");
            };
            i = i + 1;
        };
    };
};

// ============================================================================
// Deck — owns and shuffles the cards
// ============================================================================

object Deck
{
    int[52] cards;
    int     top;
    PCG32*  rng;

    def __init(PCG32* rng) -> this
    {
        this.rng = rng;
        this.top = 0;
        int i = 0;
        while (i < 52)
        {
            this.cards[i] = i;
            i = i + 1;
        };
        this.shuffle();
        return this;
    };

    def __exit() -> void
    {
        return;
    };

    def shuffle() -> void
    {
        int i = 51;
        while (i > 0)
        {
            int j       = random_range_int(this.rng, 0, i);
            int tmp     = this.cards[i];
            this.cards[i] = this.cards[j];
            this.cards[j] = tmp;
            i = i - 1;
        };
        this.top = 0;
    };

    def deal() -> int
    {
        if (52 - this.top < 15)
        {
            this.shuffle();
        };
        int card  = this.cards[this.top];
        this.top  = this.top + 1;
        return card;
    };
};

// ============================================================================
// Game — orchestrates a full session
// ============================================================================

object Game
{
    PCG32 rng;
    Deck  deck;
    Hand  player;
    Hand  dealer;
    int   chips;

    def __init() -> this
    {
        pcg32_init(@this.rng);
        this.deck  = Deck(@this.rng);
        this.chips = 100;
        return this;
    };

    def __exit() -> void
    {
        return;
    };

    def read_int() -> int
    {
        byte[16] buf;
        input(buf, 15);
        int val = 0;
        int i   = 0;
        while (buf[i] >= '0' & buf[i] <= '9')
        {
            val = val * 10 + (buf[i] - '0');
            i   = i + 1;
        };
        return val;
    };

    def read_char() -> byte
    {
        byte[4] buf;
        input(buf, 3);
        return buf[0];
    };

    def settle(int bet) -> int
    {
        int pval = this.player.value();
        int dval = this.dealer.value();

        if (this.player.is_bust())                                  { return 0 - bet; };
        if (this.player.is_blackjack())
        {
            if (this.dealer.is_blackjack())                         { return 0; };
            return bet + bet / 2;
        };
        if (this.dealer.is_bust())                                  { return bet; };
        if (pval > dval)                                            { return bet; };
        if (pval == dval)                                           { return 0; };
        return 0 - bet;
    };

    def print_summary(int bet) -> void
    {
        print("\n--- Summary ---\n\0");

        print("Dealer: \0");
        this.dealer.print_cards(false);
        print(" = \0");
        print(this.dealer.value());
        print("\n\0");

        print("Player: \0");
        this.player.print_cards(false);
        print(" = \0");
        print(this.player.value());
        print("\n\0");

        int delta = this.settle(bet);

        if (this.player.is_bust())
        {
            print("Bust! You lose.\n\0");
        }
        elif (this.player.is_blackjack() & !this.dealer.is_blackjack())
        {
            print("Blackjack! You win 3:2.\n\0");
        }
        elif (delta > 0)
        {
            print("You win!\n\0");
        }
        elif (delta == 0)
        {
            print("Push.\n\0");
        }
        else
        {
            print("You lose.\n\0");
        };
    };

    def play_round() -> void
    {
        print("\nChips: \0");
        print(this.chips);
        print("\n\0");
        print("Bet (0 to quit): \0");

        int bet = this.read_int();

        if (bet == 0) { return; };
        if (bet < 1)  { bet = 1; };
        if (bet > this.chips) { bet = this.chips; };

        this.player.clear();
        this.dealer.clear();

        this.player.add(this.deck.deal());
        this.dealer.add(this.deck.deal());
        this.player.add(this.deck.deal());
        this.dealer.add(this.deck.deal());

        print("\nDealer: \0");
        this.dealer.print_cards(true);
        print("\nPlayer: \0");
        this.player.print_cards(false);
        print(" = \0");
        print(this.player.value());
        print("\n\0");

        // Player turn — skip if blackjack
        if (!this.player.is_blackjack())
        {
            bool done = false;
            while (!done & !this.player.is_bust())
            {
                print("[H]it or [S]tand? \0");
                byte c = this.read_char();

                if (c == 'h' | c == 'H')
                {
                    this.player.add(this.deck.deal());
                    print("Player: \0");
                    this.player.print_cards(false);
                    print(" = \0");
                    print(this.player.value());
                    print("\n\0");
                }
                elif (c == 's' | c == 'S')
                {
                    done = true;
                };
            };
        };

        // Dealer turn
        if (!this.player.is_bust())
        {
            while (this.dealer.value() < 17)
            {
                this.dealer.add(this.deck.deal());
            };
        };

        this.print_summary(bet);
        this.chips = this.chips + this.settle(bet);
    };

    def run() -> void
    {
        print("=== Blackjack ===\n\0");
        print("You start with 100 chips. Dealer stands on 17.\n\0");

        while (this.chips > 0)
        {
            this.play_round();
        };

        print("\nFinal chips: \0");
        print(this.chips);
        print("\n\0");
        if (this.chips <= 0) { print("Broke. Better luck next time.\n\0"); };
    };
};

// ============================================================================
// Entry point
// ============================================================================

def main() -> int
{
    Game game();
    game.run();
    game.__exit();
    return 0;
};
