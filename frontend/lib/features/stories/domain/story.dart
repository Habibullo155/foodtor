import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../catalog/data/demo_catalog.dart';

enum StoryKind {
  promo('Акция'),
  fresh('Новинка'),
  news('Новости'),
  personal('Для вас');

  const StoryKind(this.label);
  final String label;
}

@immutable
class Story {
  const Story({
    required this.id,
    required this.title,
    required this.kind,
    required this.coverUrl,
    required this.slides,
    this.color = const Color(0xFF0B5D3B),
  });

  final String id;
  final String title;
  final StoryKind kind;
  final String coverUrl;
  final List<StorySlide> slides;
  final Color color; // фон кружка и слайдов (фото продуктов — без фона)
}

@immutable
class StorySlide {
  const StorySlide({
    required this.imageUrl,
    required this.headline,
    this.caption,
    this.ctaLabel,
    this.ctaCategoryId,
  });
  final String imageUrl;
  final String headline;
  final String? caption;
  final String? ctaLabel; // «Смотреть подборку»
  final int? ctaCategoryId; // deep link в категорию
}

/// В проде: GET /api/v1/stories (бэкенд учитывает сегмент: B2B видит свои предложения).
final storiesProvider = Provider<List<Story>>(
  // В релизе историй нет, пока их не заведёт контент-менеджер (лента скрывается целиком)
  (ref) => !AppConfig.isDemo
      ? const <Story>[]
      : [
          Story(
            id: 'berries',
            title: 'Сезон ягод',
            kind: StoryKind.promo,
            color: const Color(0xFFE11D48),
            coverUrl: ingredientImage('Strawberries'),
            slides: [
              StorySlide(
                imageUrl: ingredientImage('Strawberries'),
                headline: 'Клубника −20%',
                caption: 'Собрана вчера, у вас — сегодня',
                ctaLabel: 'Смотреть ягоды',
                ctaCategoryId: 3,
              ),
              StorySlide(
                imageUrl: ingredientImage('Blueberries'),
                headline: 'Голубика из Марокко',
                caption: 'Новый урожай',
              ),
            ],
          ),
          Story(
            id: 'farm',
            title: 'Фермерское',
            kind: StoryKind.fresh,
            color: const Color(0xFF16A34A),
            coverUrl: ingredientImage('Carrots'),
            slides: [
              StorySlide(
                imageUrl: ingredientImage('Carrots'),
                headline: 'Овощи от Фермы Иванова',
                caption: 'Без посредников, прямо с грядки',
                ctaLabel: 'К овощам',
                ctaCategoryId: 1,
              ),
            ],
          ),
          Story(
            id: 'pasta',
            title: 'Рецепт дня',
            kind: StoryKind.news,
            color: const Color(0xFFD97706),
            coverUrl: ingredientImage('Spaghetti'),
            slides: [
              StorySlide(
                imageUrl: ingredientImage('Spaghetti'),
                headline: 'Паста помодоро за 15 минут',
              ),
              StorySlide(
                imageUrl: ingredientImage('Plum Tomatoes'),
                headline: 'Сливовидные томаты',
                caption: '+ чеснок',
              ),
              StorySlide(
                imageUrl: ingredientImage('Basil'),
                headline: 'Финальный штрих — базилик',
                ctaLabel: 'Собрать корзину',
                ctaCategoryId: 6,
              ),
            ],
          ),
          Story(
            id: 'for-you',
            title: 'Для вас',
            kind: StoryKind.personal,
            color: const Color(0xFF4CAF50),
            coverUrl: ingredientImage('Avocado'),
            slides: [
              StorySlide(
                imageUrl: ingredientImage('Avocado'),
                headline: 'Промокод FRESH300',
                caption: '−300 ₽ от 1500 ₽',
              ),
            ],
          ),
          Story(
            id: 'delivery',
            title: 'За 2 часа',
            kind: StoryKind.news,
            color: const Color(0xFF0891B2),
            coverUrl: ingredientImage('Lemon'),
            slides: [
              StorySlide(
                imageUrl: ingredientImage('Lemon'),
                headline: 'Экспресс-доставка за 2 часа',
                caption: 'Свежее — значит быстро',
              ),
            ],
          ),
          Story(
            id: 'pantry',
            title: 'Бакалея',
            kind: StoryKind.fresh,
            color: const Color(0xFFCA8A04),
            coverUrl: ingredientImage('Quinoa'),
            slides: [
              StorySlide(
                imageUrl: ingredientImage('Quinoa'),
                headline: 'Киноа, нут, кускус',
                caption: 'Новинки на полке круп',
                ctaLabel: 'К крупам',
                ctaCategoryId: 5,
              ),
            ],
          ),
          Story(
            id: 'b2b',
            title: 'Бизнесу',
            kind: StoryKind.news,
            color: const Color(0xFF334155),
            coverUrl: ingredientImage('Potatoes'),
            slides: [
              StorySlide(
                imageUrl: ingredientImage('Potatoes'),
                headline: 'Опт для кафе и магазинов',
                caption: 'Оставьте заявку в профиле',
              ),
            ],
          ),
        ],
);

/// Просмотренные сторис — кольцо становится серым. В проде хранится локально (shared_preferences).
class SeenStoriesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void markSeen(String id) => state = {...state, id};
}

final seenStoriesProvider = NotifierProvider<SeenStoriesNotifier, Set<String>>(
  SeenStoriesNotifier.new,
);
