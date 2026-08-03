# BSP 交互式 bash 小优化（所有用户）
# 仅交互式 shell
case $- in
	*i*) ;;
	*) return ;;
esac

# 常用别名
alias ll='ls -alF --color=auto' 2>/dev/null || alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'

# ifconfig/ip 提示（若仍找不到，说明 profile.d 未加载）
if ! command -v ifconfig >/dev/null 2>&1 && [ -x /sbin/ifconfig ]; then
	alias ifconfig='/sbin/ifconfig'
fi
if ! command -v ip >/dev/null 2>&1 && [ -x /sbin/ip ]; then
	alias ip='/sbin/ip'
fi

# 串口/SSH 下少一些乱码宽表问题
export SYSTEMD_COLORS="${SYSTEMD_COLORS:-0}"
