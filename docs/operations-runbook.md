# OpenShift 운영 점검 Runbook

명령을 단순 나열하지 않고, **현재 대상 확인 → 클러스터 상태 확인 → Workload 점검 → Pod/노드 심화 진단** 순서로 구성했습니다. 모든 예시의 이름은 placeholder이며, 실제 인증 정보와 내부 주소를 저장소에 기록하지 않습니다.

## 1. 접속 대상과 권한 확인

비밀번호나 토큰을 명령 기록·스크립트·README에 직접 적지 않습니다. 필요한 경우 조직의 인증 절차로 로그인한 뒤 사용자, API 서버, Context를 먼저 확인합니다.

```bash
oc login <api-server>
oc whoami
oc whoami --show-server
oc config current-context
oc version
```

웹 콘솔 주소를 확인할 수 있는 권한이 있다면 다음 명령을 사용합니다.

```bash
oc whoami --show-console
```

`~/.kube/config`에는 접속 정보와 토큰이 포함될 수 있으므로 출력 전체를 이슈나 저장소에 첨부하지 않습니다.

## 2. 프로젝트 선택

OpenShift Project는 Kubernetes Namespace를 확장한 리소스입니다. 새 프로젝트 생성은 쓰기 작업이므로 먼저 현재 프로젝트와 권한을 확인합니다.

```bash
oc project
oc get project
oc auth can-i create projects.project.openshift.io

oc new-project <project-name>
oc project <project-name>
```

기존 프로젝트를 선택하기만 할 때는 `oc project <project-name>`을 사용합니다. Kubernetes Context의 Namespace를 직접 바꿔야 한다면 명령은 `kubectl config set-context --current --namespace=<namespace>`이며, `set-contexts`가 아닙니다.

## 3. Operator 상태 구분

`ClusterOperator`는 OpenShift 플랫폼 구성 요소의 상태를, OLM(Operator Lifecycle Manager) 리소스는 설치한 Add-on Operator의 구독과 버전을 보여줍니다.

```bash
# 플랫폼 Operator: Available=True, Progressing=False, Degraded=False를 우선 확인
oc get clusteroperators
oc get clusteroperator dns -o yaml
oc get pods -n openshift-dns-operator

# OLM으로 설치한 Operator
oc get subscriptions.operators.coreos.com -A
oc get clusterserviceversions.operators.coreos.com -A
```

`oc get operators`만으로 두 종류의 상태를 모두 판단하지 않습니다.

## 4. 클러스터 상태 1차 점검

변경을 가하지 않는 조회 명령으로 전체 상태를 좁혀 갑니다.

```bash
oc cluster-info
oc get clusteroperators
oc get nodes -o wide
oc get events -A --sort-by=.lastTimestamp
```

Metrics API와 권한이 있는 환경에서는 사용량도 확인합니다.

```bash
oc adm top node
oc adm top pod -A --sum
oc adm top pod <pod-name> -n <namespace> --containers
```

플랫폼 모니터링 Namespace의 정확한 이름은 `openshift-monitoring`입니다.

```bash
oc get pods -n openshift-monitoring
oc get events -n openshift-monitoring --sort-by=.lastTimestamp
```

`oc cluster-info dump`는 출력량이 많고 내부 정보가 포함될 수 있으므로 공개 터미널 로그나 저장소 파일로 바로 남기지 않습니다. 지원 자료로 수집할 때는 별도 보안 저장 위치와 공유 범위를 먼저 정합니다.

## 5. Pod 문제 좁히기

```bash
oc get pods -n <namespace> -o wide
oc describe pod <pod-name> -n <namespace>
oc logs <pod-name> -n <namespace> --tail=100
oc logs <pod-name> -n <namespace> -c <container-name> --tail=100
oc logs <pod-name> -n <namespace> -c <container-name> --previous --tail=100
```

컨테이너가 정상 실행 중이고 RBAC가 허용하면 `oc exec`로 필요한 명령만 실행합니다. 원본 Pod를 직접 변경하거나 재현이 어려운 진단이 필요하면 복제된 Debug Pod를 사용합니다.

```bash
oc exec <pod-name> -n <namespace> -c <container-name> -- <command>
oc debug pod/<pod-name> -n <namespace>
oc debug job/<job-name> -n <namespace>
```

강제 삭제(`--force --grace-period=0`)는 데이터 손실이나 중복 실행을 일으킬 수 있으므로 일반 복구 절차로 사용하지 않습니다. Controller 상태와 정상 종료 실패 원인을 먼저 확인합니다.

## 6. 노드와 CRI-O 심화 진단

노드 진단은 관리자 권한이 필요한 최후 단계입니다. 먼저 Node Condition과 kubelet/CRI-O 로그를 확인합니다.

```bash
oc describe node <node-name>
oc adm node-logs <node-name> -u kubelet --tail=100
oc adm node-logs <node-name> -u crio --tail=100
```

호스트 파일 시스템 또는 컨테이너 Runtime 수준의 확인이 필요한 경우에만 Debug Pod를 사용합니다.

```bash
oc debug node/<node-name>
chroot /host
crictl ps
crictl inspect <container-id>
```

컨테이너 프로세스의 Linux Namespace를 확인할 때는 `crictl inspect`에서 PID를 찾은 뒤 `lsns`로 범위를 확인합니다. `nsenter`는 호스트 root 권한으로 격리를 우회하므로, 진단 목적과 대상 PID를 검증한 경우에만 사용합니다.

```bash
crictl inspect <container-id> -o json | jq '.info.pid'
lsns -p <pid>
nsenter -t <pid> -n -- ip address
```

일반 애플리케이션 점검은 `oc logs` → `oc exec` → `oc debug` 순서로 수행하고, `nsenter`를 기본 접근 수단으로 사용하지 않습니다.

## 7. 이미지 확인

이미지를 실행하기 전에 Registry metadata와 설정을 조회합니다.

```bash
skopeo inspect docker://<registry>/<repository>:<tag>
skopeo inspect --config docker://<registry>/<repository>:<tag>
oc image info <registry>/<repository>:<tag>
```

Registry 로그인 정보는 전용 인증 저장소를 사용하고 명령 예시나 Git 파일에 넣지 않습니다. `latest` 같은 부동 태그는 학습 탐색에는 쓸 수 있지만, 재현성이 필요한 배포에서는 검증한 digest 또는 관리되는 ImageStream 정책을 사용합니다.

## 8. Template 처리

Template은 먼저 파라미터와 렌더링 결과를 검토한 뒤 서버 측 Dry-run으로 현재 클러스터 API와 Admission 정책을 확인합니다.

```bash
oc process -f manifests/app-template.yaml --parameters
oc process -f manifests/app-template.yaml -p IMAGE=<image-reference> -o yaml

oc process -f manifests/app-template.yaml -p IMAGE=<image-reference> \
  | oc apply --dry-run=server -f -
```

승인된 Namespace와 이미지에서 검증을 통과했을 때만 `oc apply -f -`로 실제 반영합니다.
