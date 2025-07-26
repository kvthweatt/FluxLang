import inspect
from typing import List, Dict, Type

def codegen_classes(module) -> Dict[str, Type]:
    codegen_classes = {}
    
    for name, obj in inspect.getmembers(module, inspect.isclass):
        if obj.__module__ == module.__name__:
            if hasattr(obj, 'codegen') and inspect.isfunction(getattr(obj, 'codegen')):
                codegen_classes[name] = obj
                
    return codegen_classes

def no_codegen_classes(module) -> Dict[str, Type]:
    codegen_classes = {}
    
    for name, obj in inspect.getmembers(module, inspect.isclass):
        if obj.__module__ == module.__name__:
            if hasattr(obj, 'codegen') is False:
                codegen_classes[name] = obj
            try:
                if inspect.isfunction(getattr(obj, 'codegen')) is False:
                    codegen_classes[name]= obj
            except:
                codegen_classes[name]= obj
                
    return codegen_classes

import fast
codegen_classes = codegen_classes(fast)
nocodegen = no_codegen_classes(fast)

print("## AST classes with codegen() methods:")
for class_name in sorted(codegen_classes.keys()):
    print(f"- **{class_name}**")

print("## AST classes without codegen() methods:")
for class_name in sorted(nocodegen.keys()):
    print(f"- **{class_name}**")