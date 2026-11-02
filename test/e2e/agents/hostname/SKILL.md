---
name: hostname
description: Get the user's machine's hostname
---
This bundle provides the **hostname** tool, which retrieves the user's machine's hostname.

### When to Use It
Use this bundle when you need to query the hostname of the system using this tool.

### How to Use It
To use the **hostname** tool, call it without any arguments. The script will return the hostname in the format:

```json
{"hostname": "somehostname", "message": "Current hostname retrieved successfully."}'
```

### Notes
- The result includes both the hostname and a confirmation message.
- The tool does not require any parameters.
