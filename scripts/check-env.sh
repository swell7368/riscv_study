#!/usr/bin/env bash
# riscv_study 환경 점검 스크립트. Phase 6 (Definition of Done) 하드 게이트를 확인한다.
set -u

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export PATH="$HOME/bin:$JAVA_HOME/bin:$PATH"

PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if "$@" > /tmp/check-env.out 2>&1; then
    echo "OK   - $desc"
    PASS=$((PASS+1))
  else
    echo "FAIL - $desc"
    sed 's/^/       /' /tmp/check-env.out
    FAIL=$((FAIL+1))
  fi
}

echo "== 디스크 =="
AVAIL_GB=$(df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
echo "available: ${AVAIL_GB:-?} GB"

echo
echo "== Git =="
check "git user.name 설정됨"  git config --global user.name
check "git user.email 설정됨" git config --global user.email

echo
echo "== 툴체인 버전 =="
check "java 17.x"       bash -c "java -version 2>&1 | grep -q '17\.'"
check "mill 0.11.1"     bash -c "mill --version 2>&1 | grep -q '0\.11\.1'"
check "verilator 설치됨" verilator --version
check "cmake 설치됨"     cmake --version
check "dtc 설치됨"       dtc --version

echo
echo "== 레포/서브모듈 =="
check "rocket-chip 서브모듈 존재" test -f third_party/rocket-chip/build.sc
check "Xbar.scala 존재"          test -f third_party/rocket-chip/src/main/scala/tilelink/Xbar.scala
check "unittest Configs.scala 존재" test -f third_party/rocket-chip/src/main/scala/unittest/Configs.scala

echo
echo "== 체크리스트 문서 =="
LINES=$(wc -l < docs/01-xbar-sparsity-checklist.md 2>/dev/null || echo 0)
echo "docs/01-xbar-sparsity-checklist.md: ${LINES} lines"
if [ "$LINES" -gt 150 ]; then
  echo "OK   - 체크리스트 150줄 이상"
  PASS=$((PASS+1))
else
  echo "FAIL - 체크리스트 150줄 미달"
  FAIL=$((FAIL+1))
fi

echo
echo "== 결과: ${PASS} OK / ${FAIL} FAIL =="
[ "$FAIL" -eq 0 ]
