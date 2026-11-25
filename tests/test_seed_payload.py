from scripts.seed_mock_data import (
    build_absences,
    build_calendar,
    build_departments,
    build_events,
    build_timeman,
    build_users,
    workdays,
)


def test_users_and_departments():
    users = build_users(5)
    assert len(users) == 5
    assert {u["id"] for u in users} == {1, 2, 3, 4, 5}
    assert all(u["department_names"] for u in users)

    departments = build_departments()
    assert len(departments) == 3
    assert all("code" in dep for dep in departments)


def test_workdays_excludes_weekends():
    days = workdays(14)
    assert days
    assert all(day.weekday() < 5 for day in days)


def test_events_and_timeman_are_complete():
    users = build_users(3)
    days = workdays(5)

    events = build_events(users, days)
    assert len(events) == len(users) * len(days) * 2
    assert {e["direction"] for e in events} == {"IN", "OUT"}

    timeman = build_timeman(users, days)
    assert len(timeman) == len(users) * len(days)
    assert all(row["duration"] > 0 for row in timeman)


def test_absences_and_calendar():
    users = build_users(2)
    days = workdays(5)
    absences = build_absences(users, days)
    assert len(absences) == 1
    assert absences[0]["active"] is True

    calendar = build_calendar(days)
    assert len(calendar) == len(days)
    assert all(row[5] is True for row in calendar)  # is_workday
