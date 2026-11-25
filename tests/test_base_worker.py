from app.workers.base import BaseWorker


class FakeClient:
    def __init__(self):
        self.calls = []

    def fetch(self, entity, params):
        self.calls.append((entity, params))
        return [{"id": 1}]


def test_build_params_uses_last_id(monkeypatch):
    worker = BaseWorker("scud_event", 60, FakeClient())
    monkeypatch.setattr(worker, "get_last_id", lambda: 42)
    assert worker.build_params() == {"last_id": 42}


def test_work_fetches_and_stores(monkeypatch):
    client = FakeClient()
    worker = BaseWorker("scud_event", 60, client)
    monkeypatch.setattr(worker, "build_params", lambda: {"last_id": 0})

    stored = {}
    monkeypatch.setattr(
        "app.workers.base.insert_items",
        lambda entity, items: stored.update(entity=entity, items=items),
    )

    worker.work()

    assert client.calls == [("scud_event", {"last_id": 0})]
    assert stored == {"entity": "scud_event", "items": [{"id": 1}]}


def test_work_skips_empty_batches(monkeypatch):
    client = FakeClient()
    client.fetch = lambda entity, params: []
    worker = BaseWorker("scud_event", 60, client)
    monkeypatch.setattr(worker, "build_params", lambda: {"last_id": 0})

    called = []
    monkeypatch.setattr(
        "app.workers.base.insert_items",
        lambda entity, items: called.append(entity),
    )

    worker.work()

    assert called == []
