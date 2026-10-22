// Демо-учётки админки (только локальная разработка, без бэкенда).
// Пароли здесь НЕ хранятся — только SHA-256(salt + password). Открытые пароли: DEMO_ACCOUNTS.md (в .gitignore).
// При подключении API вход идёт через POST /api/v1/auth/login (Argon2id + JWT на сервере), этот файл не используется.

class DemoAccount {
  const DemoAccount({
    required this.email,
    required this.name,
    required this.role,
    required this.salt,
    required this.hash,
  });
  final String email;
  final String name;
  final String role; // owner | manager | picker | courier
  final String salt;
  final String hash;
}

const demoAccounts = [
  DemoAccount(
    email: 'owner@saasshop.local',
    name: 'Хабиб Зухуров',
    role: 'owner',
    salt: '2a08ee633932577d',
    hash: 'dbc7adf64f08617ceb3940297a02d2273af26a42fa90696077448e69af115f68',
  ),
  DemoAccount(
    email: 'manager@saasshop.local',
    name: 'Анна Смирнова',
    role: 'manager',
    salt: '39c55c56f460751c',
    hash: '0388065867f1b04465ace30bdef636ac55ae086733b7a9275476a10fc8384049',
  ),
  DemoAccount(
    email: 'picker@saasshop.local',
    name: 'Игорь Петров',
    role: 'picker',
    salt: 'd2cdec1f4398ed05',
    hash: '4020be4ba1280da741a4f598c39b0f93a065c4d08070fd5648631ee5e29c9b38',
  ),
  DemoAccount(
    email: 'courier@saasshop.local',
    name: 'Руслан Алиев',
    role: 'courier',
    salt: '5958456277f4da75',
    hash: '0467e08b11ae944970b89eb62a3343bc5c679aa7997ccc39654a0f9e192156e0',
  ),
];
