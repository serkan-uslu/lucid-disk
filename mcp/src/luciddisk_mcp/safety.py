from __future__ import annotations

import os
from enum import Enum
from pathlib import Path

from pydantic import BaseModel


class RiskLevel(str, Enum):
    REBUILDABLE = "rebuildable"
    REVIEW = "review"
    SENSITIVE = "sensitive"
    PROTECTED = "protected"


class SafetyClassification(BaseModel):
    risk: RiskLevel
    risk_title: str
    reasons: list[str]
    recommendation: str
    matched_rule: str


RISK_TITLES = {
    RiskLevel.REBUILDABLE: "Yeniden oluşturulabilir",
    RiskLevel.REVIEW: "Önce incele",
    RiskLevel.SENSITIVE: "Hassas veri",
    RiskLevel.PROTECTED: "Korumalı",
}

RISK_PRIORITY = {
    RiskLevel.REBUILDABLE: 0,
    RiskLevel.REVIEW: 1,
    RiskLevel.SENSITIVE: 2,
    RiskLevel.PROTECTED: 3,
}


def normalize_path(path: str) -> str:
    expanded = os.path.expanduser(path.strip())
    if not expanded:
        raise ValueError("path must not be empty")
    return os.path.normpath(os.path.abspath(expanded))


def is_within(path: str, root: str) -> bool:
    try:
        return os.path.commonpath([path, root]) == root
    except ValueError:
        return False


def _classification(
    risk: RiskLevel,
    matched_rule: str,
    reason: str,
    recommendation: str,
) -> SafetyClassification:
    return SafetyClassification(
        risk=risk,
        risk_title=RISK_TITLES[risk],
        reasons=[reason],
        recommendation=recommendation,
        matched_rule=matched_rule,
    )


def classify_path(path: str, home_path: str | None = None) -> SafetyClassification:
    normalized = normalize_path(path)
    home = normalize_path(home_path or str(Path.home()))

    blocked_roots = {"/", home, "/Applications", "/Library", "/Users", "/private", "/etc", "/opt", "/usr/local"}
    if normalized in blocked_roots:
        return _classification(
            RiskLevel.PROTECTED,
            "root_location",
            "Disk, user, or machine-wide roots must not be handled as a single cleanup item.",
            "Alt öğeleri ayrı ayrı inceleyin; bu yolu silmeyin.",
        )

    if is_within(normalized, "/usr/local"):
        return _classification(
            RiskLevel.SENSITIVE,
            "machine_wide_software",
            "Bu konum makine genelindeki araçları ve paket yöneticisi verilerini içerebilir.",
            "Dosyayı oluşturan paket yöneticisi veya uygulama ile kaldırın.",
        )

    protected_roots = (
        "/System", "/bin", "/sbin", "/usr", "/var", "/private/var",
        "/Applications", "/Library",
    )
    if any(is_within(normalized, root) for root in protected_roots):
        return _classification(
            RiskLevel.PROTECTED,
            "macos_protected_system",
            "Bu yol macOS'in korunan sistem alanlarından birinde.",
            "Silme işlemi yapmayın; macOS veya ilgili yönetim aracını kullanın.",
        )

    derived_data = f"{home}/Library/Developer/Xcode/DerivedData"
    if is_within(normalized, derived_data):
        return _classification(
            RiskLevel.REBUILDABLE,
            "xcode_derived_data",
            "Xcode derleme ve indeks önbelleği gerektiğinde yeniden üretilir.",
            "Xcode kapalıyken ve aktif derleme çıktısına ihtiyacınız yokken temizlenebilir.",
        )

    xcode_archives = f"{home}/Library/Developer/Xcode/Archives"
    if is_within(normalized, xcode_archives):
        return _classification(
            RiskLevel.SENSITIVE,
            "xcode_archives",
            "Arşivler dağıtılmış sürümleri ve hata sembolizasyonunda kullanılan dSYM dosyalarını içerebilir.",
            "Önce Xcode Organizer'da sürümü ve dSYM ihtiyacını doğrulayın.",
        )

    xcode_user_data = f"{home}/Library/Developer/Xcode/UserData"
    if is_within(normalized, xcode_user_data):
        return _classification(
            RiskLevel.SENSITIVE,
            "xcode_user_data",
            "Kod parçacıkları, breakpoint'ler ve kişisel Xcode ayarları bulunabilir.",
            "İçeriğini ve yedeğini doğrulamadan silmeyin.",
        )

    simulator_devices = f"{home}/Library/Developer/CoreSimulator/Devices"
    if is_within(normalized, simulator_devices):
        return _classification(
            RiskLevel.SENSITIVE,
            "simulator_devices",
            "Simülatör uygulama verileri ve cihaz durumları bulunabilir.",
            "Ham klasör silmek yerine Xcode veya simctl ile kullanılmayan simülatörleri yönetin.",
        )

    device_support = f"{home}/Library/Developer/Xcode/iOS DeviceSupport"
    if is_within(normalized, device_support):
        return _classification(
            RiskLevel.REVIEW,
            "xcode_device_support",
            "Bağlanan iOS sürümleri için destek ve sembol verileri içerir.",
            "Eski cihaz sürümlerini doğrulayın; ihtiyaç halinde Xcode yeniden oluşturabilir.",
        )

    review_roots = (
        f"{home}/Library/Caches",
        f"{home}/Library/Logs",
        f"{home}/Downloads",
        f"{home}/.Trash",
    )
    if any(is_within(normalized, root) for root in review_roots):
        return _classification(
            RiskLevel.REVIEW,
            "reviewable_user_storage",
            "Bu konum genellikle temizlenebilir öğeler içerir, ancak kullanıcı verisi de bulunabilir.",
            "Dosya adını, oluşturan uygulamayı ve tekrar gerekli olup olmadığını doğrulayın.",
        )

    sensitive_user_roots = (
        f"{home}/Desktop",
        f"{home}/Documents",
        f"{home}/Pictures",
        f"{home}/Movies",
        f"{home}/Music",
        f"{home}/Library/Application Support",
        f"{home}/Library/CloudStorage",
        f"{home}/Library/Mail",
        f"{home}/Library/Messages",
        f"{home}/Library/Mobile Documents",
        f"{home}/.ssh",
        f"{home}/.gnupg",
    )
    if any(is_within(normalized, root) for root in sensitive_user_roots):
        return _classification(
            RiskLevel.SENSITIVE,
            "persistent_user_data",
            "Bu konum kişisel, bulutla eşitlenen veya uygulamaya ait kalıcı veri içerebilir.",
            "İlgili uygulamadan yönetin veya doğrulanmış bir yedek aldıktan sonra karar verin.",
        )

    machine_wide_roots = ("/Applications", "/Library", "/private", "/etc", "/opt")
    if any(is_within(normalized, root) for root in machine_wide_roots):
        return _classification(
            RiskLevel.SENSITIVE,
            "machine_wide_data",
            "Bu makine genelindeki bir uygulama ya da yapılandırma alanı.",
            "Dosyayı oluşturan uygulamayı belirleyip kendi kaldırma veya yönetim akışını tercih edin.",
        )

    if is_within(normalized, "/Users") and not is_within(normalized, home):
        return _classification(
            RiskLevel.SENSITIVE,
            "other_user_data",
            "Bu konum başka bir kullanıcı hesabına ait veri içerebilir.",
            "Hesap sahibinin onayı ve doğrulanmış bir yedek olmadan silmeyin.",
        )

    if is_within(normalized, home):
        return _classification(
            RiskLevel.REVIEW,
            "unknown_user_data",
            "Kullanıcı klasöründeki bu öğe için otomatik güvenli kararı verilemiyor.",
            "İçeriği, oluşturan uygulamayı, son kullanım zamanını ve yedeğini kontrol edin.",
        )

    return _classification(
        RiskLevel.REVIEW,
        "unknown_location",
        "Bu konum bilinen güvenli-temizleme kalıplarından biri değil.",
        "Silmeden önce kaynağını, içeriğini ve yedeğini doğrulayın.",
    )
