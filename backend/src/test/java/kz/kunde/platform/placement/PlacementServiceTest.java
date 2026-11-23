package kz.kunde.platform.placement;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class PlacementServiceTest {
    private static final UUID ALMATY = UUID.randomUUID();
    private static final UUID ASTANA = UUID.randomUUID();

    private record FakeLocator(String aggregate, Map<UUID, UUID> cityById) implements PlacementLocator {
        @Override
        public String domain() {
            return "food";
        }

        @Override
        public Optional<Placement> locate(UUID id) {
            return cityById.containsKey(id) ? Optional.of(new Placement(id, cityById.get(id))) : Optional.empty();
        }
    }

    private static PlacementService service(Map<UUID, UUID> data) {
        return new PlacementService(List.of(new FakeLocator("food.order", data)), new SingleShardResolver());
    }

    @Test
    void keyShapeIsValidatedFailClosed() {
        assertThatThrownBy(() -> ShardKey.city("food", null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ShardKey("food", ShardKey.Scope.GLOBAL, ALMATY)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> ShardKey.global("Food; drop")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ShardLocation("a b")).isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void singleShardResolverAnswersDefaultForEveryKind() {
        var resolver = new SingleShardResolver();
        assertThat(resolver.resolve(ShardKey.city("food", ALMATY))).isEqualTo(ShardLocation.DEFAULT);
        assertThat(resolver.resolve(ShardKey.city("food", ASTANA))).isEqualTo(new ShardLocation("default"));
        assertThat(resolver.resolve(ShardKey.global("identity")).shardId()).isEqualTo("default");
        assertThat(resolver.resolve(ShardKey.unplaced("rides")).shardId()).isEqualTo("default");
    }

    @Test
    void idLookupReadsStoredCityNotCallerState() {
        UUID almatyOrder = UUID.randomUUID();
        UUID astanaOrder = UUID.randomUUID();
        var svc = service(Map.of(almatyOrder, ALMATY, astanaOrder, ASTANA));
        assertThat(svc.locate("food.order", almatyOrder).orElseThrow().key().cityId()).isEqualTo(ALMATY);
        assertThat(svc.locate("food.order", astanaOrder).orElseThrow().key().cityId()).isEqualTo(ASTANA);
        assertThat(svc.locate("food.order", UUID.randomUUID())).isEmpty();
    }

    @Test
    void claimedCityIsOnlyComparedFailClosed() {
        UUID order = UUID.randomUUID();
        UUID unplaced = UUID.randomUUID();
        var data = new java.util.HashMap<UUID, UUID>();
        data.put(order, ALMATY);
        data.put(unplaced, null);
        var svc = service(data);
        assertThat(svc.belongsToCity("food.order", order, ALMATY)).isTrue();
        assertThat(svc.belongsToCity("food.order", order, ASTANA)).as("substituted city").isFalse();
        assertThat(svc.belongsToCity("food.order", order, null)).as("missing city").isFalse();
        assertThat(svc.belongsToCity("food.order", unplaced, ALMATY)).as("unplaced record").isFalse();
        assertThat(svc.belongsToCity("food.order", UUID.randomUUID(), ALMATY)).as("unknown id").isFalse();
        assertThat(svc.locate("food.order", unplaced).orElseThrow().key().scope()).isEqualTo(ShardKey.Scope.UNPLACED);
    }

    @Test
    void unknownAggregateAndDuplicateLocatorsFailLoudly() {
        assertThatThrownBy(() -> service(Map.of()).locate("nope", UUID.randomUUID()))
                .isInstanceOf(IllegalArgumentException.class);
        var a = new FakeLocator("food.order", Map.of());
        assertThatThrownBy(() -> new PlacementService(List.of(a, a), new SingleShardResolver()))
                .isInstanceOf(IllegalStateException.class);
    }
}
