"""Canvas 경로와 서비스 상자 침범을 정적으로 검사하여 반응형 배치의 회귀를 막는다."""
import json
from pathlib import Path

dashboard = json.loads((Path(__file__).resolve().parents[1] / 'grafana/dashboards/demo-msa.json').read_text(encoding='utf-8'))
panel = next(p for p in dashboard['panels'] if p['type'] == 'canvas')
elements = panel['options']['root']['elements']
by_name = {e['name']: e for e in elements}
assert len(by_name) == len(elements), '중복 Canvas 이름'


def box(element):
    p = element['placement']
    return p['left'], p['top'], 100 - p['left'] - p['right'], 100 - p['top'] - p['bottom']


def point(element, anchor):
    x, y, w, h = box(element)
    return x + w * (anchor['x'] + 1) / 2, y + h * (1 - anchor['y']) / 2


def cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


segments = []
main = [e for e in elements if e['name'].endswith('Service') or e['name'] in ('client', 'Kafka', 'Gateway', 'PurchaseGateway', 'Eureka', 'Saga')]
for element in elements:
    if element['name'].startswith(('kafka_', 'Saga')):
        assert element['constraint'] == {'horizontal': 'scale', 'vertical': 'scale'}
    for connection in element.get('connections', []):
        assert not connection.get('vertices'), '연결은 검증 가능한 직선 segment로 구성'
        target = by_name[connection['targetName']]
        a, b = point(element, connection['source']), point(target, connection['target'])
        segments.append((element['name'], target['name'], a, b))
        for other in main:
            if other['name'] in (element['name'], target['name']):
                continue
            x, y, w, h = box(other)
            # 직선이 사각형 내부와 겹치는 열린 매개변수 구간을 계산한다.
            low, high = 0.0, 1.0
            for start, delta, lo, hi in ((a[0], b[0] - a[0], x + 1e-7, x + w - 1e-7), (a[1], b[1] - a[1], y + 1e-7, y + h - 1e-7)):
                if abs(delta) < 1e-10:
                    if not lo < start < hi:
                        high = -1
                        break
                else:
                    bounds = sorted(((lo - start) / delta, (hi - start) / delta))
                    low, high = max(low, bounds[0]), min(high, bounds[1])
            assert low >= high, f'상자 침범: {element["name"]} -> {other["name"]}'

for i, (_, _, a, b) in enumerate(segments):
    for _, _, c, e in segments[i + 1:]:
        assert not (cross(a, b, c) * cross(a, b, e) < -1e-8 and cross(c, e, a) * cross(c, e, b) < -1e-8), '연결선 교차'

fields = {t.get('legendFormat') for t in panel['targets']}
for element in elements:
    text = element.get('config', {}).get('text', {})
    if text.get('mode') == 'field':
        assert text['field'] in fields, f'필드 바인딩 누락: {text["field"]}'
for p in dashboard['panels']:
    for t in p.get('targets', []):
        assert 'rate(kafka_topic_partition_current_offset' not in t.get('expr', ''), 'offset gauge에 rate 금지'
print(f'Canvas {len(segments)}개 연결: 교차 0, 상자 침범 0, scale 제약 및 필드 바인딩 정상')
