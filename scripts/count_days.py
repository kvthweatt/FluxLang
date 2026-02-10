#!/usr/bin/env python3
"""
Count the total number of unique days with commits in a git log.

Usage: python3 count_commit_days.py <history_file> [commit_hash]
       If commit_hash is provided, counts from present (top of log) to that commit (inclusive)
"""

import sys
import re
from datetime import datetime

def parse_git_log(filepath, from_hash=None):
    """Parse git log file and extract unique commit dates.
    
    Git log is in reverse chronological order (newest first).
    
    Args:
        filepath: Path to the git log file
        from_hash: Optional commit hash - counts from present (top) to this hash (inclusive)
    
    Returns:
        Set of unique dates as (year, month, day) tuples
    """
    unique_dates = set()
    
    # Pattern to match git log lines
    commit_pattern = re.compile(r'^commit\s+([a-f0-9]+)')
    date_pattern = re.compile(r'^Date:\s+\w+\s+(\w+)\s+(\d+)\s+\d+:\d+:\d+\s+(\d+)')
    
    # In git log, newest commits are at the top
    # If from_hash is specified, we collect from top until we hit that hash
    found_target = False
    
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            # Check for commit hash
            if from_hash:
                commit_match = commit_pattern.match(line)
                if commit_match:
                    commit_hash = commit_match.group(1)
                    # If we found the target hash, mark it but continue to get its date
                    if commit_hash.startswith(from_hash) or from_hash.startswith(commit_hash):
                        found_target = True
            
            # Check for date line
            date_match = date_pattern.match(line)
            if date_match:
                month_str, day_str, year_str = date_match.groups()
                
                # Convert month name to number
                month_num = datetime.strptime(month_str, '%b').month
                day = int(day_str)
                year = int(year_str)
                
                # Store as tuple (year, month, day)
                unique_dates.add((year, month_num, day))
                
                # If this was the date for our target hash, stop here
                if found_target:
                    break
    
    return unique_dates

def main():
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print("Usage: python3 count_commit_days.py <history_file> [commit_hash]")
        print("       If commit_hash is provided, counts from present to that commit")
        sys.exit(1)
    
    filepath = sys.argv[1]
    from_hash = sys.argv[2] if len(sys.argv) == 3 else None
    
    try:
        unique_dates = parse_git_log(filepath, from_hash)
        total_days = len(unique_dates)
        
        if from_hash:
            print(f"Total days with commits from present to {from_hash}: {total_days}")
        else:
            print(f"Total days with commits: {total_days}")
        
    except FileNotFoundError:
        print(f"Error: File '{filepath}' not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()