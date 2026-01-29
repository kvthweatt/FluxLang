#import "standard.fx";

struct ListNode;

struct ListNode
{
    int value;
    ListNode* next;
};

def list_append(ListNode* head, int value) -> ListNode*
{
    heap ListNode new_node = {value = value, next = (ListNode*)0};
    
    if (head == (ListNode*)0)
    {
        return @new_node;
    };
    
    ListNode* current = head;
    while (current.next != (ListNode*)0)
    {
        current = current.next;
    };
    
    current.next = @new_node;
    return head;
};

def list_print(ListNode* head) -> void
{
    ListNode* current = head;
    while (current != (ListNode*)0)
    {
        print(f"Value: {current->value}\0");
        current = current.next;
    };
};

def main() -> int
{
    return 0;
};