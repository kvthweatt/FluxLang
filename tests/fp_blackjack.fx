#import "standard.fx", "redrandom.fx";

using standard::random;

// ============================================================================
// Blackjack - functional style
//
// State is passed into and returned from pure functions.
// No mutable globals. No objects. Functions transform data.
// ============================================================================

// A card is an int 0..51.
// suit  = card / 13   (0=clubs 1=diamonds 2=hearts 3=spades)
// rank  = card % 13   (0=A 1=2 .. 9=10 10=J 11=Q 12=K)

struct GameState
{
    int[52] deck;
    int     deck_top;       // index of next card to deal
    int[11] player_hand;
    int     player_count;
    int[11] dealer_hand;
    int     dealer_count;
    int     chips;
    int     bet;
    bool    player_bust;
    bool    dealer_bust;
    bool    player_blackjack;
};

// ============================================================================
// Pure card helpers
// ============================================================================

def rank_of(int card) -> int
{
    return card % 13;
};

def rank_value(int rank) -> int
{
    // 0=A->11, 1-8->2-9, 9-12->10
    if (rank == 0)  { return 11; };
    if (rank >= 9)  { return 10; };
    return rank + 1;
};

def hand_value(int* hand, int count) -> int
{
    int total = 0;
    int aces  = 0;
    int i     = 0;

    while (i < count)
    {
        int r = rank_of(hand[i]);
        int v = rank_value(r);
        total = total + v;
        if (r == 0) { aces = aces + 1; };
        i = i + 1;
    };

    // Reduce aces from 11 to 1 while busted
    while (total > 21 & aces > 0)
    {
        total = total - 10;
        aces  = aces  - 1;
    };

    return total;
};

def is_bust(int* hand, int count) -> bool
{
    return hand_value(hand, count) > 21;
};

def is_blackjack(int* hand, int count) -> bool
{
    return count == 2 & hand_value(hand, count) == 21;
};

// ============================================================================
// Pure deck helpers
// ============================================================================

def make_deck(int* deck) -> void
{
    int i = 0;
    while (i < 52)
    {
        deck[i] = i;
        i = i + 1;
    };
};

def shuffle_deck(int* deck, PCG32* rng) -> void
{
    int i = 51;
    while (i > 0)
    {
        int j = random_range_int(rng, 0, i);
        int tmp  = deck[i];
        deck[i]  = deck[j];
        deck[j]  = tmp;
        i = i - 1;
    };
};

// Deal one card from the top of the deck; returns the card.
// Advances deck_top in the state.
def deal_card(GameState* gs) -> int
{
    int card     = gs.deck[gs.deck_top];
    gs.deck_top  = gs.deck_top + 1;
    return card;
};

// ============================================================================
// Print helpers
// ============================================================================

def rank_name(int rank) -> byte*
{
    if (rank == 0)  { return "A\0"; };
    if (rank == 1)  { return "2\0"; };
    if (rank == 2)  { return "3\0"; };
    if (rank == 3)  { return "4\0"; };
    if (rank == 4)  { return "5\0"; };
    if (rank == 5)  { return "6\0"; };
    if (rank == 6)  { return "7\0"; };
    if (rank == 7)  { return "8\0"; };
    if (rank == 8)  { return "9\0"; };
    if (rank == 9)  { return "10\0"; };
    if (rank == 10) { return "J\0"; };
    if (rank == 11) { return "Q\0"; };
    return "K\0";
};

def suit_name(int suit) -> byte*
{
    if (suit == 0) { return "C\0"; };
    if (suit == 1) { return "D\0"; };
    if (suit == 2) { return "H\0"; };
    return "S\0";
};

def print_card(int card) -> void
{
    print(rank_name(rank_of(card)));
    print(suit_name(card / 13));
};

def print_hand(int* hand, int count, bool hide_first) -> void
{
    int i = 0;
    while (i < count)
    {
        if (i == 0 & hide_first)
        {
            print("[?]\0");
        }
        else
        {
            print("[");
            print_card(hand[i]);
            print("]\0");
        };
        i = i + 1;
    };
};

// ============================================================================
// Round setup — pure transform: initialise a fresh round into gs
// ============================================================================

def setup_round(GameState* gs, PCG32* rng, int bet) -> void
{
    // Reshuffle when fewer than 15 cards remain
    if (52 - gs.deck_top < 15)
    {
        shuffle_deck(@gs.deck[0], rng);
        gs.deck_top = 0;
    };

    gs.player_count    = 0;
    gs.dealer_count    = 0;
    gs.bet             = bet;
    gs.player_bust     = false;
    gs.dealer_bust     = false;
    gs.player_blackjack = false;

    // Deal: player, dealer, player, dealer
    gs.player_hand[gs.player_count] = deal_card(gs);
    gs.player_count = gs.player_count + 1;

    gs.dealer_hand[gs.dealer_count] = deal_card(gs);
    gs.dealer_count = gs.dealer_count + 1;

    gs.player_hand[gs.player_count] = deal_card(gs);
    gs.player_count = gs.player_count + 1;

    gs.dealer_hand[gs.dealer_count] = deal_card(gs);
    gs.dealer_count = gs.dealer_count + 1;
};

// ============================================================================
// Player turn — pure transform: hit or stand mutates gs
// ============================================================================

def player_hit(GameState* gs) -> void
{
    gs.player_hand[gs.player_count] = deal_card(gs);
    gs.player_count = gs.player_count + 1;
    gs.player_bust  = is_bust(@gs.player_hand[0], gs.player_count);
};

// ============================================================================
// Dealer turn — dealer hits on soft 16, stands on 17+
// ============================================================================

def dealer_play(GameState* gs) -> void
{
    while (hand_value(@gs.dealer_hand[0], gs.dealer_count) < 17)
    {
        gs.dealer_hand[gs.dealer_count] = deal_card(gs);
        gs.dealer_count = gs.dealer_count + 1;
    };
    gs.dealer_bust = is_bust(@gs.dealer_hand[0], gs.dealer_count);
};

// ============================================================================
// Settle — pure function: returns chip delta
// ============================================================================

def settle(GameState* gs) -> int
{
    int pval = hand_value(@gs.player_hand[0], gs.player_count);
    int dval = hand_value(@gs.dealer_hand[0], gs.dealer_count);

    if (gs.player_bust)                            { return 0 - gs.bet; };
    if (gs.player_blackjack & !gs.dealer_bust)
    {
        // Check dealer also has blackjack
        if (is_blackjack(@gs.dealer_hand[0], gs.dealer_count)) { return 0; };
        // Blackjack pays 3:2
        return gs.bet + gs.bet / 2;
    };
    if (gs.dealer_bust)                            { return gs.bet; };
    if (pval > dval)                               { return gs.bet; };
    if (pval == dval)                              { return 0; };
    return 0 - gs.bet;
};

// ============================================================================
// Print round summary
// ============================================================================

def print_summary(GameState* gs) -> void
{
    print("\n--- Summary ---\n\0");
    print("Dealer: \0");
    print_hand(@gs.dealer_hand[0], gs.dealer_count, false);
    print(" = \0");
    print(hand_value(@gs.dealer_hand[0], gs.dealer_count));
    print("\n\0");

    print("Player: \0");
    print_hand(@gs.player_hand[0], gs.player_count, false);
    print(" = \0");
    print(hand_value(@gs.player_hand[0], gs.player_count));
    print("\n\0");

    int delta = settle(gs);

    if (gs.player_bust)
    {
        print("Bust! You lose.\n\0");
    }
    elif (gs.player_blackjack & !is_blackjack(@gs.dealer_hand[0], gs.dealer_count))
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

// ============================================================================
// Input helpers
// ============================================================================

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

// ============================================================================
// Main game loop
// ============================================================================

def main() -> int
{
    PCG32 rng;
    pcg32_init(@rng);

    GameState gs;
    gs.chips    = 100;
    gs.deck_top = 0;

    make_deck(@gs.deck[0]);
    shuffle_deck(@gs.deck[0], @rng);

    print("=== Blackjack ===\n\0");
    print("You start with 100 chips. Dealer stands on 17.\n\0");

    while (gs.chips > 0)
    {
        print("\nChips: \0");
        print(gs.chips);
        print("\n\0");
        print("Bet (0 to quit): \0");

        int bet = read_int();

        if (bet == 0)   { break; };
        if (bet < 1)    { bet = 1; };
        if (bet > gs.chips) { bet = gs.chips; };

        setup_round(@gs, @rng, bet);

        gs.player_blackjack = is_blackjack(@gs.player_hand[0], gs.player_count);

        // Show initial state
        print("\nDealer: \0");
        print_hand(@gs.dealer_hand[0], gs.dealer_count, true);
        print("\nPlayer: \0");
        print_hand(@gs.player_hand[0], gs.player_count, false);
        print(" = \0");
        print(hand_value(@gs.player_hand[0], gs.player_count));
        print("\n\0");

        // Player turn — skip if blackjack
        if (!gs.player_blackjack)
        {
            bool player_done = false;
            while (!player_done & !gs.player_bust)
            {
                print("[H]it or [S]tand? \0");
                byte c = read_char();

                if (c == 'h' | c == 'H')
                {
                    player_hit(@gs);
                    print("Player: \0");
                    print_hand(@gs.player_hand[0], gs.player_count, false);
                    print(" = \0");
                    print(hand_value(@gs.player_hand[0], gs.player_count));
                    print("\n\0");
                }
                elif (c == 's' | c == 'S')
                {
                    player_done = true;
                };
            };
        };

        // Dealer turn — only if player didn't bust
        if (!gs.player_bust)
        {
            dealer_play(@gs);
        };

        print_summary(@gs);

        int delta  = settle(@gs);
        gs.chips   = gs.chips + delta;
    };

    print("\nFinal chips: \0");
    print(gs.chips);
    print("\n\0");
    if (gs.chips <= 0) { print("Broke. Better luck next time.\n\0"); };

    return 0;
};
