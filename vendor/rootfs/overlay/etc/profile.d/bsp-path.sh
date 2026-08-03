# BSP：普通用户也能直接用 ifconfig / ip / 管理工具
# Debian 默认非 root PATH 不含 /sbin、/usr/sbin
if [ "$(id -u)" -ne 0 ]; then
	case ":${PATH}:" in
		*:/usr/sbin:*) ;;
		*) PATH="/usr/local/sbin:/usr/sbin:/sbin:${PATH}" ;;
	esac
	export PATH
fi
