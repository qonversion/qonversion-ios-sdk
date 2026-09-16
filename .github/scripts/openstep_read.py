"""Minimal read-only OpenStep plist parser for checked-in Xcode project validation."""
import json
import re

TOKEN = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,"]+', re.S)

def parse(text):
    tokens=[]; position=0
    for match in TOKEN.finditer(text):
        if match.start()!=position: raise ValueError('Unrecognized OpenStep token')
        position=match.end(); value=match.group()
        if value.isspace() or value.startswith(('/*','//')): continue
        tokens.append(json.loads(value) if value.startswith('"') else value)
    if position!=len(text): raise ValueError('Trailing OpenStep input')
    index=0
    def take(expected=None):
        nonlocal index
        if index>=len(tokens): raise ValueError('Unexpected end')
        value=tokens[index]; index+=1
        if expected is not None and value!=expected: raise ValueError('Unexpected OpenStep delimiter')
        return value
    def value():
        item=take()
        if item=='{':
            result={}
            while tokens[index]!='}':
                key=take(); take('=')
                if key in result: raise ValueError('Duplicate key')
                result[key]=value(); take(';')
            take('}'); return result
        if item=='(':
            result=[]
            while tokens[index]!=')':
                result.append(value())
                if tokens[index]==',':take(',')
                elif tokens[index]!=')':raise ValueError('Missing comma')
            take(')'); return result
        return item
    result=value()
    if index!=len(tokens): raise ValueError('Trailing tokens')
    return result
