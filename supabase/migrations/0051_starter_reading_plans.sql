-- 0051_starter_reading_plans.sql
-- Original Mathetes starter journeys for the CCCFSP FUOYE pilot. These are
-- short invitations, not a replacement for pastoral teaching or copyrighted
-- third-party study material. Future parishes receive their own content.

with pilot as (
  select id from public.parishes where slug = 'cccfsp-fuoye'
)
insert into public.reading_plans (
  parish_id, slug, title, description, length_days, difficulty,
  sequence_locked, published, published_at
)
select pilot.id, plans.slug, plans.title, plans.description, 7, plans.difficulty,
       true, true, now()
from pilot
cross join (
  values
    ('story-of-the-old-testament', 'The Story of the Old Testament', 'Seven anchors for seeing the Old Testament as one unfolding story of God, promise, rescue, wisdom, exile, and hope.', 'starter'),
    ('jesus-and-the-new-testament', 'Jesus & the New Testament', 'Seven days following the good news from Jesus'' ministry to the Church''s everyday witness.', 'starter'),
    ('wisdom-for-campus-life', 'Wisdom for Campus Life', 'Seven honest conversations with God about work, friendships, decisions, integrity, rest, and influence.', 'intermediate'),
    ('a-life-of-prayer', 'A Life of Prayer', 'Seven gentle practices for turning everyday moments into a real conversation with God.', 'starter')
) as plans(slug, title, description, difficulty)
on conflict (parish_id, slug) do nothing;

with pilot_plans as (
  select p.id, p.slug
  from public.reading_plans p
  join public.parishes parish on parish.id = p.parish_id
  where parish.slug = 'cccfsp-fuoye'
    and p.slug in (
      'story-of-the-old-testament',
      'jesus-and-the-new-testament',
      'wisdom-for-campus-life',
      'a-life-of-prayer'
    )
), days as (
  select * from (values
    -- The Story of the Old Testament
    ('story-of-the-old-testament', 1, 'A good beginning', 'Genesis 1:1–31', 'The Bible opens with a God who speaks life into being and calls his world good. Before the story becomes complicated, notice that creation begins with gift, purpose, and God''s presence.', 'Where do you need to receive your life today as a gift from God rather than a problem to solve?'),
    ('story-of-the-old-testament', 2, 'Promise in the ordinary', 'Genesis 12:1–9', 'God meets Abram in an ordinary place and invites him into a promise larger than his own plans. Faith often starts with a next step before the whole road is visible.', 'What faithful next step is in front of you, even if you cannot see the full outcome?'),
    ('story-of-the-old-testament', 3, 'A God who rescues', 'Exodus 3:1–15', 'At the burning bush, God sees suffering, hears cries, and moves toward his people. The rescue story is not about human strength; it is about God''s faithful presence.', 'Where do you need to remember that God sees and hears you?'),
    ('story-of-the-old-testament', 4, 'Learning a wise way', 'Deuteronomy 6:4–9', 'God gives Israel a way of life that reaches homes, conversations, routines, and memory. Formation grows when God''s words are carried into normal moments.', 'Choose one ordinary moment today where you can return your attention to God.'),
    ('story-of-the-old-testament', 5, 'Songs for real life', 'Psalm 23', 'The Psalms teach us to bring the whole of life to God: trust, fear, joy, doubt, and need. Prayer does not require pretending that everything is fine.', 'What honest sentence do you want to say to your Shepherd today?'),
    ('story-of-the-old-testament', 6, 'When we wander', '2 Kings 17:7–15', 'Exile reminds us that small compromises can slowly shape a people away from God. Yet even hard consequences do not cancel God''s long patience and mercy.', 'What small pattern is pulling your heart away from the life God wants for you?'),
    ('story-of-the-old-testament', 7, 'Hope for a new heart', 'Ezekiel 36:24–28', 'The Old Testament ends by pointing forward: God promises cleansing, a new heart, and his Spirit within his people. The story prepares us to recognise Jesus as God''s faithful answer.', 'Thank God for one way he is changing your heart from the inside out.'),

    -- Jesus & the New Testament
    ('jesus-and-the-new-testament', 1, 'The kingdom comes near', 'Mark 1:14–20', 'Jesus begins his public ministry with good news: God''s kingdom is near. His invitation is not merely to know facts, but to turn, trust, and follow.', 'What might it look like to follow Jesus in one concrete part of your day?'),
    ('jesus-and-the-new-testament', 2, 'A different kind of strength', 'Matthew 5:1–16', 'Jesus calls blessed the people the world may overlook: the humble, merciful, hungry for what is right, and makers of peace. Kingdom strength looks like Christ.', 'Which beatitude challenges the way you normally measure a good life?'),
    ('jesus-and-the-new-testament', 3, 'Grace at the table', 'Luke 19:1–10', 'Jesus sees Zacchaeus before Zacchaeus has anything to offer. Grace welcomes, restores, and then reshapes the way a person lives.', 'Where do you need to receive Jesus'' welcome instead of trying to earn it?'),
    ('jesus-and-the-new-testament', 4, 'Love that lays itself down', 'John 13:1–17', 'Jesus washes his disciples'' feet and gives them a pattern for love. Christian leadership and friendship are formed by humble service, not self-importance.', 'Who can you serve quietly this week?'),
    ('jesus-and-the-new-testament', 5, 'The risen Jesus sends', 'Matthew 28:16–20', 'The resurrection does not end the story; it sends ordinary disciples into the world with Jesus'' authority and presence. We witness because he is with us.', 'Name one person or place where you want to carry the presence of Jesus well.'),
    ('jesus-and-the-new-testament', 6, 'A community learns to share life', 'Acts 2:42–47', 'The early church devoted itself to teaching, prayer, meals, generosity, and shared life. Faith grows best when it becomes a community rhythm.', 'What is one way you can show up more faithfully for your house or fellowship?'),
    ('jesus-and-the-new-testament', 7, 'Sent into ordinary places', '1 Peter 2:9–12', 'The New Testament calls believers a people who belong to God and reflect his goodness in the world. Your campus, room, and friendships are places of witness.', 'Ask God to make your everyday life point gently to him.'),

    -- Wisdom for Campus Life
    ('wisdom-for-campus-life', 1, 'Work with your whole heart', 'Colossians 3:23–24', 'Study can feel heavy, competitive, or invisible. Paul reframes work as an offering to the Lord, giving even ordinary effort a deeper purpose.', 'What would it change if you approached one task today as service to Christ?'),
    ('wisdom-for-campus-life', 2, 'Choose friends who sharpen you', 'Proverbs 13:20', 'Friendships shape our imagination and habits over time. Wisdom is not isolation; it is learning to walk closely with people who move us toward life.', 'Who helps you love God and others more truthfully?'),
    ('wisdom-for-campus-life', 3, 'Bring your decisions to God', 'Proverbs 3:5–6', 'Trusting God does not mean switching off your mind. It means refusing to make your own understanding the final authority.', 'What decision are you carrying alone that you can place before God today?'),
    ('wisdom-for-campus-life', 4, 'Integrity in the small things', 'Luke 16:10', 'Character is formed in the places no one applauds: honest words, clean work, faithful promises, and responsible choices.', 'What small act of integrity is God inviting you to practise today?'),
    ('wisdom-for-campus-life', 5, 'Rest is not failure', 'Mark 6:30–32', 'Jesus invites tired disciples to come away and rest. Rest is not laziness when it helps us return to God, people, and work with a whole heart.', 'What would a small, life-giving pause with God look like today?'),
    ('wisdom-for-campus-life', 6, 'Words that build', 'Ephesians 4:29', 'Our words can carry grace into group chats, rooms, classrooms, and homes. Before speaking, ask whether your words will strengthen another person.', 'Choose one person to encourage with a specific, truthful word today.'),
    ('wisdom-for-campus-life', 7, 'Use influence as service', 'Mark 10:42–45', 'Jesus refuses the world''s definition of greatness. Influence becomes holy when it is used to make room, lift burdens, and serve people.', 'Where can you use your voice or position to make life better for someone else?'),

    -- A Life of Prayer
    ('a-life-of-prayer', 1, 'Begin with attention', 'Psalm 46:10', 'Prayer can begin with stillness. You do not need polished words before God; begin by noticing that he is present and you are not alone.', 'Sit quietly for two minutes. What do you notice as you become still before God?'),
    ('a-life-of-prayer', 2, 'Speak honestly', 'Psalm 62:8', 'God invites us to pour out our hearts, not hide them. Honest prayer makes room for fear, disappointment, gratitude, and desire.', 'Write one honest sentence you have been holding back from God.'),
    ('a-life-of-prayer', 3, 'Ask for daily bread', 'Matthew 6:9–13', 'Jesus teaches us to bring ordinary needs to our Father. Daily bread includes enough strength, wisdom, provision, and grace for this day.', 'What is your daily bread need today? Ask simply and specifically.'),
    ('a-life-of-prayer', 4, 'Pray for another person', 'James 5:16', 'Prayer turns our attention outward. Carrying someone before God is a practical way to love them, even when you cannot fix everything.', 'Pray by name for one friend, family member, or house mate.'),
    ('a-life-of-prayer', 5, 'Listen with Scripture open', 'Hebrews 4:12', 'God often reshapes us as we sit with his living Word. Reading slowly is not wasted time; it is a way of making room to hear and respond.', 'Read today''s passage twice. Which word or phrase stays with you?'),
    ('a-life-of-prayer', 6, 'Give thanks in the middle', '1 Thessalonians 5:16–18', 'Thanksgiving does not deny difficulty. It teaches our hearts to notice God''s gifts and faithfulness even while we are still waiting.', 'List three specific gifts from today and thank God for them.'),
    ('a-life-of-prayer', 7, 'Carry prayer into the day', 'Colossians 4:2', 'A praying life is not limited to a quiet corner. Stay awake to God through lectures, meals, travel, conflict, and joy.', 'Set one simple reminder that will bring you back to God later today.')
  ) as v(plan_slug, day_number, title, scripture_reference, reflection_body, reflection_prompt)
)
insert into public.reading_plan_days (
  plan_id, day_number, title, scripture_reference, reflection_body, reflection_prompt
)
select p.id, d.day_number, d.title, d.scripture_reference, d.reflection_body, d.reflection_prompt
from days d
join pilot_plans p on p.slug = d.plan_slug
on conflict (plan_id, day_number) do nothing;
