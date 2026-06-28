## Style Guide
- UPPER_SNAKE_CASE is for global variables that are const or are effectively const (set once)
- Special generated types using PerCpuDyn, RcuPtr, etc should be camelCase
- TitleCase is reserved for regular types
- enum entries should be UPPER_SNAKE_CASE
- Functions, global variables, and type fields should be camelCase
- Local variables should be camelCase but can be snake_case