"""
Прогоняется против РЕАЛЬНОГО Postgres — не SQLite. SQLite сериализует
все записи на уровне всей БД (а не строки), поэтому не может физически
воспроизвести сценарий "две параллельные незакоммиченные транзакции
пишут разные строки одновременно", который и есть суть этого бага.

Как запустить локально (в проекте уже есть docker-compose с сервисом db):

    docker compose up -d db
    DATABASE_URL=postgresql+psycopg2://seenly:seenly@localhost:5432/seenly \
        python3 backend/scripts/verify_co_view_vote_race.py

Бьёт напрямую в router-функции (без HTTP-слоя, но с реальными
SQLAlchemy-сессиями/транзакциями/блокировками): заводит двух тестовых
пользователей, партнёрскую связь, общий тайтл в обоих watchlist'ах,
стартует раунд и через threading шлёт оба "да" по-настоящему
одновременно. Без фикса это зависает в status=active навсегда
(assert упадёт); с фиксом — оба "да" всё равно закрывают раунд матчем,
кто бы из двух потоков ни отработал последним.
"""
import threading
import uuid
import asyncio

from sqlalchemy.orm import sessionmaker

from app.database import engine
from app import models
from app.routers.co_view_vote import cast_vote, start_vote
from app.schemas import CoViewVoteCastRequest

Session = sessionmaker(bind=engine)


def make_user(db, name):
    u = models.User(
        id=str(uuid.uuid4()),
        username=f"{name}-{uuid.uuid4().hex[:8]}",
        password_hash="x",
        display_name=name,
    )
    db.add(u)
    db.commit()
    return u


def main():
    setup_db = Session()
    alice = make_user(setup_db, "alice")
    bob = make_user(setup_db, "bob")
    link = models.PartnerLink(
        id=str(uuid.uuid4()),
        code=uuid.uuid4().hex[:8],
        owner_id=alice.id,
        partner_id=bob.id,
        status=models.PartnerLinkStatus.active,
    )
    setup_db.add(link)
    setup_db.commit()

    # Один и тот же тайтл в личном watchlist обоих -> "personal"-пул
    # голосования будет непустым и с этим тайтлом внутри.
    for u in (alice, bob):
        setup_db.add(models.WatchlistEntry(
            id=str(uuid.uuid4()),
            user_id=u.id,
            source="tmdb",
            media_id="42",
            media_type=models.MediaType.movie,
            status=models.WatchStatus.watch_later,
        ))
    setup_db.commit()

    round_db = Session()
    session_out = asyncio.run(start_vote(source="personal", current_user=alice, db=round_db))
    round_db.commit()
    session_id = session_out.id
    media = session_out.deck[0]
    print(f"Раунд создан: {session_id}, голосуем за {media.source}:{media.id}")

    barrier = threading.Barrier(2)  # оба потока стартуют cast_vote в один момент
    results = {}
    errors = {}

    def vote(who):
        db = Session()
        try:
            barrier.wait()
            out = cast_vote(
                session_id=session_id,
                payload=CoViewVoteCastRequest(source=media.source, media_id=media.id, decision=True),
                current_user=who,
                db=db,
            )
            db.commit()
            results[who.display_name] = out.status
        except Exception as exc:  # noqa: BLE001 — test harness, want to see everything
            errors[who.display_name] = repr(exc)
        finally:
            db.close()

    t_alice = threading.Thread(target=vote, args=(alice,))
    t_bob = threading.Thread(target=vote, args=(bob,))
    t_alice.start()
    t_bob.start()
    t_alice.join()
    t_bob.join()

    print("Результаты:", results)
    if errors:
        print("Ошибки:", errors)

    final_db = Session()
    final = final_db.get(models.CoViewVoteSession, session_id)
    print("Финальный статус раунда:", final.status, "| winner:", final.winner_source, final.winner_media_id)

    assert final.status == models.CoViewVoteStatus.done and final.winner_source is not None, (
        "БАГ ВОСПРОИЗВЕДЁН: оба проголосовали 'да' одновременно, но матч "
        "не сработал ни у кого — раунд завис в status=active."
    )
    print("OK: одновременное 'да' от обоих партнёров корректно закрыло раунд матчем.")


if __name__ == "__main__":
    main()
