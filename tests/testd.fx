#import "standard.fx";

using standard::io::console;

// Enum for game states
enum GameState
{
    MENU,
    PLAYING,
    GAME_OVER
};

// Struct for player data
struct Player
{
    char[50] name;
    int score;
    int lives;
};

// Initialize a player
def createPlayer(char[] playerName) -> Player
{
    Player p;
    
    // Copy name
    for (int i = 0; i < 50; i++)
    {
        p.name[i] = playerName[i];
        if (playerName[i] == 0)
        {
            break;
        };
    };
    
    p.score = 0;
    p.lives = 3;
    
    return p;
};

// Print player info
def showPlayer(Player p) -> void
{
    print("Player: \0");
    print(p.name);
    print("\nScore: \0");
    print(p.score);
    print("\nLives: \0");
    print(p.lives);
    print();
    return;
};

// Add points to player
def addScore(Player* p, int points) -> void
{
    p.score = p.score + points;
    return;
};

// Remove a life
def loseLife(Player* p) -> bool
{
    if (p.lives > 0)
    {
        p.lives--;
        return true;  // Still alive
    };
    return false;  // Game over
};

def main() -> int
{
    GameState state = GameState.MENU;
    
    print("=== Simple Game Demo ===\n\n\0");
    
    // Create player
    char[] playerName = "Hero\0";
    Player player = createPlayer(playerName);
    
    print("Starting game...\n\0");
    state = GameState.PLAYING;
    
    showPlayer(player);
    print(); // Empty prints newline
    
    // Game loop simulation
    for (int turn = 1; turn <= 5; turn++)
    {
        print("--- Turn \0");
        print(turn);
        print(" ---\n\0");
        
        // Add some points
        addScore(@player, turn * 10);
        print("Gained \0");
        print(turn * 10);
        print(" points!\n\0");
        
        // Random life loss
        if (turn % 2 == 0)
        {
            print("Hit by enemy!\n\0");
            bool alive = loseLife(@player);
            
            if (!alive)
            {
                print("\n*** GAME OVER ***\n\0");
                state = GameState.GAME_OVER;
                break;
            };
        };
        
        showPlayer(player);
        print("\n\0");
    };
    
    // Final results
    if (state == GameState.PLAYING)
    {
        print("*** YOU WIN! ***\n\0");
    };
    
    print("\nFinal \0");
    showPlayer(player);
    
    return 0;
};