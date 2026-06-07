# Mathetes Data Model

Entity notes and relationships. Filled in as the schema grows.

## Migration history

| Migration | Adds |
|-----------|------|
| 0001_init_identity.sql | parishes, houses, user_profiles, user_privacy, handle_new_user trigger, CCCFSP FUOYE seed (7 houses) |
| 0002_content.sql | devotional_series, devotionals, word_of_day, content_assets, today views |

## Identity & structure

```
parishes 1 ──< houses
parishes 1 ──< user_profiles >── houses
user_profiles 1 ──1 user_privacy
houses.leader_id ──> user_profiles.id  (set after profiles exist)
```

- A **parish** is a campus fellowship (pilot: CCCFSP FUOYE).
- A **house** is a sub-fellowship within a parish (7 in the pilot).
- A **user_profile** belongs to one parish and one house. Created automatically
  by the `handle_new_user` trigger when an auth user is inserted.
- **user_privacy** holds per-user privacy defaults (conservative by design).

### Roles
`member` < `discipler` < `house_leader` < `pastor` / `admin`

## Content

```
parishes 1 ──< devotional_series 1 ──< devotionals
parishes 1 ──< word_of_day
devotionals 1 ──< content_assets >── word_of_day
```

- **devotionals** and **word_of_day** are parish-scoped, status-gated
  (`draft` / `scheduled` / `published`) and dated by `publish_date`.
- One WOTD and one devotional per parish per day (unique constraint).
- Views `todays_word_of_day` / `todays_devotional` resolve "today" per parish.
