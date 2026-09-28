# 버전 및 호환성 판단

## 적용 기준

| 기준 | 적용 방식 |
| --- | --- |
| DO180 OpenShift Container Platform 4.18 학습 범위 | 저장소에서 다루는 운영 주제와 CLI 범위 |
| Red Hat OpenShift 4.18 공식 문서 | 학습 버전의 API·CLI 동작 확인 |
| 2026-09-28 기준 OpenShift 4.22 공식 문서 | 현재 버전에서도 핵심 방식이 유지되는지 확인 |

저장소에는 교육 자료 원문을 복제하지 않고, 직접 재구성한 예제와 운영 절차만 포함합니다.

## 현재성 결론

4.18 학습 자료 전체를 “최신 버전 코드”라고 표현하지는 않습니다. 대신 이 저장소에서 사용하는 핵심 인터페이스는 2026-09-28 검토 시점의 공식 최신 문서(4.22)와 다시 대조했습니다.

| 항목 | 저장소 기준 | 현재성 판단 |
| --- | --- | --- |
| OpenShift CLI | `oc`의 조회·로그·Debug 명령 | 4.22 CLI 문서에서도 유지 |
| 노드 진단 | `oc debug node/<name>` 후 필요한 경우 `chroot /host` | 4.22 지원 문서에서도 안내 |
| Metrics | `oc adm top node`, `oc adm top pod` | 4.22 CLI 문서에서도 제공 |
| Template | `template.openshift.io/v1` | 4.22 API에서 Compatibility level 1로 제공 |

따라서 “너무 오래되어 사용할 수 없는 코드”는 아니지만, 클러스터 버전·설치 Operator·RBAC·Admission 정책에 따라 결과가 달라질 수 있습니다. 실행 환경에서 다음 순서로 확인합니다.

```bash
oc version
oc api-resources | grep -E '(^NAME|templates)'
oc explain deployment.spec
oc process -f manifests/app-template.yaml --parameters
oc process -f manifests/app-template.yaml -p IMAGE=<image-reference> \
  | oc apply --dry-run=server -f -
```

## 명령과 표현 교정

| 원문 표현 | 반영 내용 | 이유 |
| --- | --- | --- |
| `kubectl config set-contexts` | `kubectl config set-context` | 실제 하위 명령 이름 교정 |
| `opensift-monitoring` | `openshift-monitoring` | Namespace 오탈자 교정 |
| `skopeo lgoin` | `skopeo login` | 명령 오탈자 교정 |
| `spect` | `spec` | Manifest 필드 오탈자 교정 |
| 명령에 평문 DB 비밀번호 작성 | 예제에서 제거, Secret/외부 주입 원칙 명시 | Shell history·프로세스 목록·Git 노출 방지 |
| Pod 강제 삭제를 일반 명령처럼 나열 | 위험과 사용 조건을 Runbook에 명시 | 정상 종료 우회에 따른 데이터 손실 방지 |
| `oc get operators` 단독 확인 | ClusterOperator와 OLM 리소스를 분리 조회 | 플랫폼 상태와 Add-on 설치 상태의 의미 구분 |

## 이미지 버전 정책

학습 범위에는 UBI 8·9 이미지와 `latest` 또는 생략된 태그가 함께 등장합니다. 이 저장소의 Template은 특정 이미지를 기본값으로 고정하지 않고 `IMAGE`를 필수 파라미터로 받습니다.

- 학습 환경: 대상 클러스터에서 접근하고 실행할 수 있는 이미지를 지정합니다.
- 반복 가능한 검증: image digest를 기록합니다.
- 조직 환경: 승인된 내부 Registry와 ImageStream 정책을 따릅니다.
- 버전 변경: `oc image info` 또는 `skopeo inspect`로 이미지 metadata를 먼저 확인합니다.

## 공식 확인 링크

- [OpenShift Container Platform 문서](https://docs.redhat.com/en/documentation/openshift_container_platform/)
- [OpenShift 4.18 CLI 도구](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/cli_tools/openshift-cli-oc)
- [OpenShift 4.22 CLI 도구](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/cli_tools/openshift-cli-oc)
- [Template API 4.22](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/template_apis/template-template-openshift-io-v1)
- [OpenShift Container Platform Life Cycle Policy](https://access.redhat.com/support/policy/updates/openshift)
