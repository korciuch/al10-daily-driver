### Issue Title:
Conflict with --now, --root, and --global usage in systemctl

### Description:
This issue arises when attempting to use the --now option in combination with --root or --global flags in systemctl. These options conflict because --now is intended for real-time service management on a live system, whereas --root is used for managing offline system roots and --global for user services globally.

### Steps to reproduce:
1. Run systemctl with the --now flag and either --root=<path> or --global, e.g., `systemctl --root=/path/to/root enable --now some-service`.

### Expected behavior:
The service should be enabled or started as appropriate.

### Actual behavior:
The operation is refused.

### Potential Solutions:
- Avoid using --now in conjunction with --root or --global.
- Clarify systemctl documentation to highlight this conflict.

### Environment:
Please specify system details and versions used.

### Additional Information:
Fixing this issue might involve splitting operations dependent on live state from those which manipulate inactive or global configurations.