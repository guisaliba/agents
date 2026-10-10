#!/usr/bin/env bash
# Distribution families supported by the approved installer.
pi_port_platform() {
  case " $1 ${2:-} " in
    *' arch '*) printf 'arch\n' ;;
    *' ubuntu '*) printf 'ubuntu\n' ;;
    *' debian '*) printf 'debian\n' ;;
    *) printf 'Unsupported Linux distribution.\n' >&2; return 1 ;;
  esac
}
