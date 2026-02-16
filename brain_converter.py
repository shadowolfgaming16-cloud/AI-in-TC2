#!/usr/bin/env python3
"""
Lua-Python Brain Format Converter
Utilities to convert between Lua nested-table format and Python JSON for weight import/export.
"""

import json
import re
from pathlib import Path
from typing import Dict, Any, List


def lua_table_to_python(lua_code: str) -> Dict:
    """
    Convert a Lua table representation to Python dict.
    Simplified parser for SENTINEL brain format.
    Handles: {key = value, nested = {a = 1}, arrays = {1, 2, 3}}
    """
    # Remove comments
    lua_code = re.sub(r'--.*?$', '', lua_code, flags=re.MULTILINE)
    
    def parse_value(s: str):
        s = s.strip()
        if s.startswith('{'):
            return parse_table(s)
        elif s.lower() in ('true', 'false'):
            return s.lower() == 'true'
        elif s.lower() == 'nil':
            return None
        elif re.match(r'-?\d+\.?\d*', s):
            return float(s) if '.' in s else int(s)
        elif s.startswith('"') or s.startswith("'"):
            return s[1:-1]
        else:
            return s
    
    def parse_table(s: str) -> Dict:
        s = s[1:-1].strip()  # Remove outer braces
        result = {}
        array_index = 1
        depth = 0
        current_key = None
        current_value = ""
        i = 0
        
        while i < len(s):
            c = s[i]
            if c in ('{', '['):
                depth += 1
            elif c in ('}', ']'):
                depth -= 1
            elif c == '=' and depth == 0:
                current_key = current_value.strip()
                current_value = ""
                i += 1
                continue
            elif c == ',' and depth == 0:
                if current_key:
                    result[current_key] = parse_value(current_value)
                    current_key = None
                else:
                    result[str(array_index)] = parse_value(current_value)
                    array_index += 1
                current_value = ""
                i += 1
                continue
            
            current_value += c
            i += 1
        
        if current_value.strip():
            if current_key:
                result[current_key] = parse_value(current_value)
            else:
                result[str(array_index)] = parse_value(current_value)
        
        return result
    
    return parse_table(lua_code)


def python_to_lua_table(obj: Any, indent: int = 0) -> str:
    """Convert Python dict/list to Lua table format."""
    prefix = "\t" * indent
    
    if isinstance(obj, dict):
        if not obj:
            return "{}"
        items = []
        for k, v in obj.items():
            if isinstance(k, str) and k.isidentifier():
                items.append(f"{prefix}\t{k} = {python_to_lua_table(v, indent + 1)}")
            else:
                items.append(f"{prefix}\t[{repr(k)}] = {python_to_lua_table(v, indent + 1)}")
        return "{\n" + ",\n".join(items) + f"\n{prefix}}}"
    elif isinstance(obj, list):
        if not obj:
            return "{}"
        items = [f"{prefix}\t{python_to_lua_table(item, indent + 1)}" for item in obj]
        return "{\n" + ",\n".join(items) + f"\n{prefix}}}"
    elif isinstance(obj, bool):
        return "true" if obj else "false"
    elif obj is None:
        return "nil"
    elif isinstance(obj, str):
        return repr(obj)
    else:
        return str(obj)


def import_brain_from_lua_file(lua_file: str) -> Dict:
    """Read a Lua file containing a brain table and convert to Python dict."""
    with open(lua_file, 'r') as f:
        content = f.read()
    
    # Extract the table assignment (e.g., "local data = {...}")
    match = re.search(r'=\s*(\{.*\})', content, re.DOTALL)
    if match:
        table_str = match.group(1)
        return lua_table_to_python(table_str)
    return {}


def export_brain_to_json(brain_dict: Dict, json_file: str):
    """Export brain dict to JSON format."""
    with open(json_file, 'w') as f:
        json.dump(brain_dict, f, indent=2)
    print(f"Brain exported to JSON: {json_file}")


def export_brain_to_lua(brain_dict: Dict, lua_file: str):
    """Export brain dict to Lua table format."""
    lua_code = f"local brain = {python_to_lua_table(brain_dict)}\nreturn brain"
    with open(lua_file, 'w') as f:
        f.write(lua_code)
    print(f"Brain exported to Lua: {lua_file}")


def import_json_to_lua_format(json_file: str, lua_file: str):
    """Convert JSON brain to Lua table format."""
    with open(json_file, 'r') as f:
        brain_dict = json.load(f)
    export_brain_to_lua(brain_dict, lua_file)


def import_lua_to_json_format(lua_file: str, json_file: str):
    """Convert Lua brain to JSON format."""
    brain_dict = import_brain_from_lua_file(lua_file)
    export_brain_to_json(brain_dict, json_file)


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Lua-Python Brain Format Converter")
    parser.add_argument("--lua-to-json", metavar="LUA_FILE", help="Convert Lua file to JSON")
    parser.add_argument("--json-to-lua", metavar="JSON_FILE", help="Convert JSON file to Lua")
    parser.add_argument("--output", metavar="OUTPUT_FILE", required=True, help="Output file")
    
    args = parser.parse_args()
    
    if args.lua_to_json:
        import_lua_to_json_format(args.lua_to_json, args.output)
    elif args.json_to_lua:
        import_json_to_lua_format(args.json_to_lua, args.output)
    else:
        parser.print_help()
